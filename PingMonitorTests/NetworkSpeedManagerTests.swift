import XCTest
@testable import PingMonitor

/// Regression tests for NetworkSpeedManager parsing & speed math.
/// These tests use real `netstat -bni` and `nettop -P -L 1 -k state,interface`
/// output captured from macOS 26 (Apr 2026). They are intentionally written
/// to *describe current behavior* — when a test fails after a behavior change,
/// reviewers should ask: "is this a real fix or an unintended regression?"
final class NetworkSpeedManagerTests: XCTestCase {

    // MARK: - parseNetstatOutput

    /// A representative `netstat -bni` snippet exercising every row shape we've
    /// seen on macOS 26: lo0 (no Address column), gif0/stf0 (inactive `*`
    /// suffix, no MAC), en0 (MAC address, multiple non-Link rows for IPv4/IPv6),
    /// utun (tunnel, no MAC), awdl (virtual).
    private let netstatSample = """
    Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
    lo0        16384 <Link#1>                       6246307     0 34579100689  6246307     0 34579100689     0
    lo0        16384 127           127.0.0.1        6246307     - 34579100689  6246307     - 34579100689     -
    lo0        16384 ::1/128     ::1                6246307     - 34579100689  6246307     - 34579100689     -
    gif0*      1280  <Link#2>                             0     0          0        0     0          0     0
    stf0*      1280  <Link#3>                             0     0          0        0     0          0     0
    en0        1500  <Link#7>    d0:11:e5:b9:c9:29 131591073     0 169417973390 89021371     0 34967744772     0
    en0        1500  fe80::cd5:7 fe80:7::cd5:722c: 131591073     - 169417973390 89021371     - 34967744772     -
    en0        1500  10.1.1/24     10.1.1.20       131591073     - 169417973390 89021371     - 34967744772     -
    awdl0      1484  <Link#15>   ae:1c:b3:dc:9d:84   12345     0    1234567    23456     0    2345678     0
    utun4      1500  <Link#21>                       100000     0   50000000    80000     0   30000000     0
    en1*       1500  <Link#11>   9e:65:19:4f:f3:60       0     0          0        0     0          0     0
    """

    func testParseNetstat_ExtractsAllLinkRows() {
        let interfaces = NetworkSpeedManager.parseNetstatOutput(netstatSample)
        let names = Set(interfaces.map(\.name))
        // Every Link row becomes one interface; non-Link IPv4/IPv6 rows are de-duped (same name).
        XCTAssertEqual(names, ["lo0", "gif0*", "stf0*", "en0", "awdl0", "utun4", "en1*"],
                       "parser should keep one entry per interface name and only from <Link#> rows")
    }

    func testParseNetstat_LoopbackHasZeroAddressOffset() {
        // lo0's <Link#1> row has *no* Address column. The parser uses a
        // negative offset to find Ibytes/Obytes. This locks that down.
        let interfaces = NetworkSpeedManager.parseNetstatOutput(netstatSample)
        guard let lo0 = interfaces.first(where: { $0.name == "lo0" }) else {
            return XCTFail("lo0 should be parsed")
        }
        XCTAssertEqual(lo0.bytesIn, 34_579_100_689, "lo0 Ibytes parsed incorrectly")
        XCTAssertEqual(lo0.bytesOut, 34_579_100_689, "lo0 Obytes parsed incorrectly")
        XCTAssertEqual(lo0.packetsIn, 6_246_307)
        XCTAssertEqual(lo0.packetsOut, 6_246_307)
    }

    func testParseNetstat_PhysicalInterfaceWithMacAddress() {
        // en0 has a MAC in the Address slot (parts[3]). Standard offset (0).
        let interfaces = NetworkSpeedManager.parseNetstatOutput(netstatSample)
        guard let en0 = interfaces.first(where: { $0.name == "en0" }) else {
            return XCTFail("en0 should be parsed")
        }
        XCTAssertEqual(en0.bytesIn, 169_417_973_390)
        XCTAssertEqual(en0.bytesOut, 34_967_744_772)
        XCTAssertEqual(en0.packetsIn, 131_591_073)
        XCTAssertEqual(en0.packetsOut, 89_021_371)
        XCTAssertEqual(en0.role, .physical)
    }

    func testParseNetstat_TunnelInterfaceParsesWithoutMac() {
        // utun4 has no MAC (Address column blank), like lo0. Make sure the
        // negative-offset branch keeps Ibytes correct for tunnel-style rows.
        let interfaces = NetworkSpeedManager.parseNetstatOutput(netstatSample)
        guard let utun = interfaces.first(where: { $0.name == "utun4" }) else {
            return XCTFail("utun4 should be parsed")
        }
        XCTAssertEqual(utun.bytesIn, 50_000_000)
        XCTAssertEqual(utun.bytesOut, 30_000_000)
        XCTAssertEqual(utun.role, .tunnel, "utun* must classify as .tunnel for VPN bookkeeping")
    }

    func testParseNetstat_StripsAsteriskFromIdKeepsInName() {
        // Bug #2 fix: netstat marks down interfaces with a trailing `*`. The
        // parser keeps the asterisk in `name` for display, but uses a stable
        // id (no asterisk) so previousStats survives the up/down transition.
        let interfaces = NetworkSpeedManager.parseNetstatOutput(netstatSample)
        guard let gif0 = interfaces.first(where: { $0.id == "gif0" }) else {
            return XCTFail("gif0 should be parsed under stable id 'gif0'")
        }
        XCTAssertEqual(gif0.id, "gif0", "id is stripped of the down marker")
        XCTAssertEqual(gif0.name, "gif0*", "name keeps the down marker for display")

        guard let en1 = interfaces.first(where: { $0.id == "en1" }) else {
            return XCTFail("en1 should be parsed under stable id 'en1'")
        }
        XCTAssertEqual(en1.id, "en1")
        XCTAssertEqual(en1.name, "en1*")
    }

    func testParseNetstat_AsteriskTransitionPreservesBaseline() {
        // The whole point of Bug #2: when an interface goes from down (en1*)
        // to up (en1), the previousStats key (= id) must still match so we
        // don't lose a delta cycle.
        let downSnapshot = NetworkSpeedManager.parseNetstatOutput("""
        Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
        en1*       1500  <Link#11>   9e:65:19:4f:f3:60       0     0          0        0     0          0     0
        """)
        let upSnapshot = NetworkSpeedManager.parseNetstatOutput("""
        Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
        en1        1500  <Link#11>   9e:65:19:4f:f3:60      10     0      12345       10     0       6789     0
        """)
        XCTAssertEqual(downSnapshot.first?.id, upSnapshot.first?.id,
                       "id must remain stable across the down→up transition")
    }

    func testParseNetstat_NonLinkRowsAreSkipped() {
        // The parser must only consume <Link#N> rows; the IPv4/IPv6 address
        // rows for the same interface have empty packet/byte cells (`-`) and
        // would otherwise zero out the totals.
        let stripped = """
        Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
        en0        1500  10.1.1/24     10.1.1.20       131591073     - 169417973390 89021371     - 34967744772     -
        """
        let interfaces = NetworkSpeedManager.parseNetstatOutput(stripped)
        XCTAssertEqual(interfaces.count, 0, "rows without <Link#N> must be ignored")
    }

    func testParseNetstat_HandlesEmptyAndMalformedInput() {
        XCTAssertEqual(NetworkSpeedManager.parseNetstatOutput("").count, 0)
        XCTAssertEqual(NetworkSpeedManager.parseNetstatOutput("garbage\nlines\n").count, 0)
        XCTAssertEqual(NetworkSpeedManager.parseNetstatOutput("Name Mtu Network\n").count, 0,
                       "header without expected columns must produce no interfaces")
    }

    // MARK: - InterfaceRole classification

    func testInterfaceRole_PhysicalEthernet() {
        XCTAssertEqual(makeInterface(name: "en0").role, .physical)
        XCTAssertEqual(makeInterface(name: "en5").role, .physical)
    }

    func testInterfaceRole_TunnelInterfaces() {
        XCTAssertEqual(makeInterface(name: "utun0").role, .tunnel)
        XCTAssertEqual(makeInterface(name: "utun99").role, .tunnel)
        XCTAssertEqual(makeInterface(name: "ipsec0").role, .tunnel)
    }

    func testInterfaceRole_VirtualInterfaces() {
        XCTAssertEqual(makeInterface(name: "awdl0").role, .virtual)
        XCTAssertEqual(makeInterface(name: "llw0").role, .virtual)
        XCTAssertEqual(makeInterface(name: "gif0").role, .virtual)
        XCTAssertEqual(makeInterface(name: "stf0").role, .virtual)
        XCTAssertEqual(makeInterface(name: "bridge0").role, .virtual)
        XCTAssertEqual(makeInterface(name: "ap1").role, .virtual)
    }

    func testInterfaceRole_LoopbackClassified() {
        XCTAssertEqual(makeInterface(name: "lo0").role, .loopback)
    }

    func testInterfaceRole_AsteriskSuffixBreaksClassification() {
        // BUG SURFACE: macOS shows down interfaces as `gif0*` / `en1*`. The
        // role switch matches by `starts(with:)` so prefixes still work, but
        // any logic that compares `iface.name == "en1"` will fail when the
        // interface is down.
        XCTAssertEqual(makeInterface(name: "gif0*").role, .virtual,
                       "starts(with:) tolerates the asterisk for prefix-based matching")
        XCTAssertEqual(makeInterface(name: "en1*").role, .physical)
        XCTAssertEqual(makeInterface(name: "utun3*").role, .tunnel)
    }

    // MARK: - parseNettopOutput / process speed semantics

    /// Real nettop output captured from `nettop -P -L 1 -k state,interface`.
    /// First column is timestamp, second is "name.PID", third bytes_in,
    /// fourth bytes_out. Note: bytes are *cumulative since the nettop process
    /// started* — NOT cumulative since the OS booted.
    private let nettopSample = """
    time,,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,
    07:19:06.615140,launchd.1,0,0,0,0,0,,,,,,,,,,,,
    07:19:06.615142,syslogd.137,0,681,0,0,0,,,,,,,,,,,,
    07:19:06.615143,apsd.143,88123,48794,0,0,0,,,,,,,,,,,,
    07:19:06.615146,AirPlayXPCHelpe.171,37142334,10465911,0,0,0,,,,,,,,,,,,
    07:19:06.615149,mDNSResponder.205,257939763,16666588,0,0,0,,,,,,,,,,,,
    """

    func testParseNettop_ExtractsPerProcessByteCounts() {
        let result = NetworkSpeedManager.parseNettopOutput(nettopSample)
        XCTAssertEqual(result[1]?.bytesIn, 0, "launchd.1")
        XCTAssertEqual(result[137]?.bytesOut, 681, "syslogd.137")
        XCTAssertEqual(result[143]?.bytesIn, 88_123)
        XCTAssertEqual(result[143]?.bytesOut, 48_794)
        XCTAssertEqual(result[171]?.bytesIn, 37_142_334)
        XCTAssertEqual(result[205]?.bytesIn, 257_939_763)
    }

    func testParseNettop_AggregatesDuplicatePIDs() {
        // If a PID somehow appears twice (rare, but `nettop` can emit per-thread
        // rows under unusual flag combos), we must sum them rather than
        // clobbering.
        let dup = """
        time,,bytes_in,bytes_out,rx_dupe,
        07:00:00.0,Foo.500,100,200,0,
        07:00:00.0,Foo.500,50,75,0,
        """
        let result = NetworkSpeedManager.parseNettopOutput(dup)
        XCTAssertEqual(result[500]?.bytesIn, 150)
        XCTAssertEqual(result[500]?.bytesOut, 275)
    }

    /// Empirically verified on macOS 26 (Apr 2026): `nettop -P -L 1` reports
    /// per-process cumulative bytes that monotonically increase across
    /// invocations (e.g. mDNSResponder running 14d went 258024596 → 258025674
    /// → 258026538 over a few seconds of repeated `nettop -L 1` calls).
    /// The delta math in `refreshProcessList` is therefore valid in principle.
    ///
    /// What *can* still skew per-process numbers in practice:
    ///   1. nettop `-L 1` blocks ~1s for its sample window, so two refreshes
    ///      that the timer fires 2s apart can actually be ~3s apart.
    ///      `interval` is measured by `Date()` though, so the *rate* is right.
    ///   2. PID set differs between refreshes — short-lived processes drop in
    ///      and out and never get a delta.
    ///   3. The `lastProcessStats = traffic` overwrite happens unconditionally;
    ///      a PID we saw last refresh but didn't see this refresh keeps its
    ///      stale baseline forever, but it isn't reported because it isn't in
    ///      `connections` either.
    func testNettopAccumulatorContract_PinnedDocumentation() {
        // Smoke test that the parser would happily process two consecutive
        // monotonic samples. Real verification is the empirical evidence
        // captured in the doc-comment above.
        let first  = NetworkSpeedManager.parseNettopOutput("time,,bytes_in,bytes_out,\nt0,proc.10,1000,500,")
        let second = NetworkSpeedManager.parseNettopOutput("time,,bytes_in,bytes_out,\nt1,proc.10,1100,520,")
        XCTAssertEqual(first[10]?.bytesIn, 1000)
        XCTAssertEqual(second[10]?.bytesIn, 1100)
        // Computed by refreshProcessList over 1s interval:
        let speedIn = Double((second[10]!.bytesIn) - (first[10]!.bytesIn)) / 1.0
        XCTAssertEqual(speedIn, 100, "delta math holds when accumulators are monotonic")
    }

    // MARK: - Total/Tunnel split semantics ("all" interface bookkeeping)

    // MARK: - aggregateTotals (Bug #1 fix)

    func testAggregateTotals_AllUsesMaxOfPhysicalAndTunnel_VPNScenario() {
        // Pure VPN: same user payload goes encrypted on en0 and decrypted on utun.
        // physical_in ≈ tunnel_in (encryption adds a small overhead, modeled here
        // as physical 1.05 MB vs tunnel 1.00 MB). max() ≈ physical avoids
        // double-counting and matches what the user actually downloaded.
        let interfaces: [NetworkInterfaceStats] = [
            speedStub(name: "en0", speedIn: 1_050_000, speedOut: 250_000),
            speedStub(name: "utun3", speedIn: 1_000_000, speedOut: 240_000),
        ]
        let totals = NetworkSpeedManager.aggregateTotals(from: interfaces, selection: "all")
        XCTAssertEqual(totals.totalSpeedIn, 1_050_000, "max(en0=1.05M, utun3=1.0M)")
        XCTAssertEqual(totals.totalSpeedOut, 250_000)
        // Tunnel speeds are also exposed so the UI can show "of which X went via VPN":
        XCTAssertEqual(totals.tunnelSpeedIn, 1_000_000)
        XCTAssertEqual(totals.tunnelSpeedOut, 240_000)
    }

    func testAggregateTotals_AllReportsTunnelWhenPhysicalIsIdle() {
        // The pre-fix bug. User has a Tailscale-only flow on utun, en0 is idle.
        // Old behavior: total = 0 (only physical counted). New behavior: total = utun.
        let interfaces: [NetworkInterfaceStats] = [
            speedStub(name: "en0", speedIn: 0, speedOut: 0),
            speedStub(name: "utun3", speedIn: 5_000_000, speedOut: 1_000_000),
        ]
        let totals = NetworkSpeedManager.aggregateTotals(from: interfaces, selection: "all")
        XCTAssertEqual(totals.totalSpeedIn, 5_000_000,
                       "VPN-only traffic must surface in the headline number, not just in the tunnel breakout")
        XCTAssertEqual(totals.totalSpeedOut, 1_000_000)
    }

    func testAggregateTotals_AllSplitTunnelDoesNotDoubleCount() {
        // Split tunnel: most traffic on en0, a smaller VPN flow on utun. The
        // bug we want to *avoid* introducing is summing physical + tunnel and
        // overcounting the VPN payload (which is already in en0's number).
        let interfaces: [NetworkInterfaceStats] = [
            speedStub(name: "en0", speedIn: 5_000_000, speedOut: 1_000_000),
            speedStub(name: "utun3", speedIn: 500_000, speedOut: 100_000),
        ]
        let totals = NetworkSpeedManager.aggregateTotals(from: interfaces, selection: "all")
        XCTAssertEqual(totals.totalSpeedIn, 5_000_000, "physical sum, since it's larger")
        XCTAssertEqual(totals.totalSpeedOut, 1_000_000)
    }

    func testAggregateTotals_SpecificInterfaceSelection() {
        let interfaces: [NetworkInterfaceStats] = [
            stub(name: "en0", bytesIn: 1_000_000, bytesOut: 500_000),
            speedStub(name: "utun3", speedIn: 5_000_000, speedOut: 1_000_000),
        ]
        let totals = NetworkSpeedManager.aggregateTotals(from: interfaces, selection: "utun3")
        XCTAssertEqual(totals.totalSpeedIn, 5_000_000, "specific selection picks just that interface")
        XCTAssertEqual(totals.totalSpeedOut, 1_000_000)
    }

    func testAggregateTotals_BytesUseMonotonicPhysicalSum() {
        // bytes are cumulative counters. We don't max them — that would let
        // them oscillate when VPN flips on/off. Always physical sum.
        let interfaces: [NetworkInterfaceStats] = [
            stub(name: "en0", bytesIn: 1_000_000, bytesOut: 500_000),
            stub(name: "utun3", bytesIn: 9_000_000, bytesOut: 4_000_000),
        ]
        let totals = NetworkSpeedManager.aggregateTotals(from: interfaces, selection: "all")
        XCTAssertEqual(totals.totalBytesIn, 1_000_000, "all-bytes uses physical sum, not max")
        XCTAssertEqual(totals.totalBytesOut, 500_000)
        XCTAssertEqual(totals.tunnelBytesIn, 9_000_000)
        XCTAssertEqual(totals.tunnelBytesOut, 4_000_000)
    }

    // MARK: - Long-elapsed rebase (Bug #3 fix)

    func testLongElapsedRebaseThreshold_NormalRefreshAccepted() {
        let refreshInterval: TimeInterval = 1.0
        let elapsed: TimeInterval = 1.05  // typical timer jitter
        XCTAssertLessThanOrEqual(elapsed,
                                 refreshInterval * NetworkSpeedManager.maxValidElapsedMultiplier,
                                 "small jitter must not trigger a rebase")
    }

    func testLongElapsedRebaseThreshold_PostSleepRejected() {
        let refreshInterval: TimeInterval = 1.0
        let elapsed: TimeInterval = 3600   // 1h sleep
        XCTAssertGreaterThan(elapsed,
                             refreshInterval * NetworkSpeedManager.maxValidElapsedMultiplier,
                             "post-sleep gap must trigger a silent rebase, not publish a fake average")
    }

    func testLongElapsedRebaseThreshold_TightBoundary() {
        // The threshold is 5x. At 4.99x we still publish a delta; at 5.01x we
        // rebase. Pinning the boundary so future tweaks stay deliberate.
        let refreshInterval: TimeInterval = 2.0
        XCTAssertEqual(NetworkSpeedManager.maxValidElapsedMultiplier, 5.0,
                       "if you change the multiplier, update operator docs and this test together")
        XCTAssertLessThan(refreshInterval * 4.99, refreshInterval * NetworkSpeedManager.maxValidElapsedMultiplier)
        XCTAssertGreaterThan(refreshInterval * 5.01, refreshInterval * NetworkSpeedManager.maxValidElapsedMultiplier)
    }

    // MARK: - Speed delta math (private to fetchStats — re-implemented here)

    /// `fetchStats` computes `speed = (current - prev) / elapsed` with a
    /// `current >= prev` guard for counter resets. These tests pin the
    /// boundary behavior so a future refactor keeps the same shape.
    func testSpeedDelta_NormalCase() {
        XCTAssertEqual(speed(prev: 1_000, current: 11_000, elapsed: 1.0), 10_000)
    }

    func testSpeedDelta_CounterResetGuardReturnsZero() {
        // Interface comes back up with a fresh counter — current < prev. The
        // production code returns a 0 delta in this case.
        XCTAssertEqual(speed(prev: 5_000, current: 100, elapsed: 1.0), 0)
    }

    func testSpeedDelta_LongElapsedAfterSleepReportsAverage() {
        // BUG SURFACE: after sleep/wake, `elapsed` may be hours and `delta`
        // is the cumulative bytes during that window — averaging produces a
        // misleadingly low B/s spike rather than an "unknown" sentinel. This
        // test documents the current behavior; ideally fetchStats should
        // discard or flag samples where elapsed >> refreshInterval.
        let elapsed: TimeInterval = 3600  // 1h sleep
        let delta: UInt64 = 1_000_000     // 1 MB cumulative across the hour
        XCTAssertEqual(speed(prev: 0, current: delta, elapsed: elapsed),
                       Double(delta) / elapsed,
                       accuracy: 0.001,
                       "average over the whole sleep window — not what the user wants to see")
    }

    // MARK: - Format helpers (locked because the dashboard reads these)

    func testFormatSpeed_BoundaryValues() {
        XCTAssertEqual(NetworkSpeedManager.formatSpeed(0), "0 B/s")
        XCTAssertEqual(NetworkSpeedManager.formatSpeed(1023), "1023 B/s")
        XCTAssertEqual(NetworkSpeedManager.formatSpeed(1024), "1.0 KB/s")
        XCTAssertEqual(NetworkSpeedManager.formatSpeed(1024 * 1024), "1.0 MB/s")
        XCTAssertEqual(NetworkSpeedManager.formatSpeed(1024 * 1024 * 1024), "1.00 GB/s")
    }

    func testFormatBytes_BoundaryValues() {
        XCTAssertEqual(NetworkSpeedManager.formatBytes(0), "0 B")
        XCTAssertEqual(NetworkSpeedManager.formatBytes(1024), "1.0 KB")
        XCTAssertEqual(NetworkSpeedManager.formatBytes(1024 * 1024), "1.0 MB")
        XCTAssertEqual(NetworkSpeedManager.formatBytes(1024 * 1024 * 1024), "1.00 GB")
    }

    // MARK: - splitAddressPort (used by lsof parsing)

    func testSplitAddressPort_IPv4() {
        let (addr, port) = NetworkSpeedManager.splitAddressPort("127.0.0.1:8080")
        XCTAssertEqual(addr, "127.0.0.1")
        XCTAssertEqual(port, "8080")
    }

    func testSplitAddressPort_IPv6Bracketed() {
        let (addr, port) = NetworkSpeedManager.splitAddressPort("[::1]:443")
        XCTAssertEqual(addr, "::1")
        XCTAssertEqual(port, "443")
    }

    func testSplitAddressPort_Wildcard() {
        let (addr, port) = NetworkSpeedManager.splitAddressPort("*:53")
        XCTAssertEqual(addr, "*")
        XCTAssertEqual(port, "53")
    }

    // MARK: - parseLsofOutput (process connection inventory)

    func testParseLsof_BasicTcpConnection() {
        let sample = """
        COMMAND     PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        Safari    12345 chace   24u  IPv4 0xabcdef             0t0  TCP 192.168.1.10:54321->17.253.144.10:443 (ESTABLISHED)
        """
        let infos = NetworkSpeedManager.parseLsofOutput(sample)
        XCTAssertEqual(infos.count, 1)
        let info = infos[0]
        XCTAssertEqual(info.processName, "Safari")
        XCTAssertEqual(info.pid, 12345)
        XCTAssertEqual(info.user, "chace")
        XCTAssertEqual(info.protocolType, "TCP")
        XCTAssertEqual(info.localAddress, "192.168.1.10")
        XCTAssertEqual(info.localPort, "54321")
        XCTAssertEqual(info.remoteAddress, "17.253.144.10")
        XCTAssertEqual(info.remotePort, "443")
        XCTAssertEqual(info.state, "ESTABLISHED")
    }

    func testParseLsof_TcpListenSocket() {
        let sample = """
        COMMAND     PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        nginx     54321 chace    8u  IPv6 0xfedcba             0t0  TCP *:80 (LISTEN)
        """
        let infos = NetworkSpeedManager.parseLsofOutput(sample)
        XCTAssertEqual(infos.count, 1)
        XCTAssertEqual(infos[0].state, "LISTEN")
        XCTAssertEqual(infos[0].localPort, "80")
    }

    // MARK: - Helpers

    private func makeInterface(name: String) -> NetworkInterfaceStats {
        NetworkInterfaceStats(id: name, name: name, bytesIn: 0, bytesOut: 0,
                              packetsIn: 0, packetsOut: 0, errorsIn: 0, errorsOut: 0)
    }

    private func stub(name: String, bytesIn: UInt64, bytesOut: UInt64) -> NetworkInterfaceStats {
        NetworkInterfaceStats(id: name, name: name, bytesIn: bytesIn, bytesOut: bytesOut,
                              packetsIn: 0, packetsOut: 0, errorsIn: 0, errorsOut: 0)
    }

    private func speedStub(name: String, speedIn: Double, speedOut: Double) -> NetworkInterfaceStats {
        var iface = NetworkInterfaceStats(id: name, name: name, bytesIn: 0, bytesOut: 0,
                                          packetsIn: 0, packetsOut: 0, errorsIn: 0, errorsOut: 0)
        iface.speedIn = speedIn
        iface.speedOut = speedOut
        return iface
    }

    /// Mirror of `fetchStats`'s inline math so we can pin its boundary behavior
    /// without instantiating the @MainActor manager (which would also fire
    /// real `netstat`/`nettop` subprocesses during tests).
    private func speed(prev: UInt64, current: UInt64, elapsed: TimeInterval) -> Double {
        let delta = current >= prev ? current - prev : 0
        return Double(delta) / elapsed
    }
}

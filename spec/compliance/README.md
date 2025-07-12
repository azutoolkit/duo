# HTTP/2 RFC 9113 Compliance Test Suite

This directory contains comprehensive compliance tests for the Duo HTTP/2 implementation, ensuring adherence to RFC 9113 (HTTP/2) and RFC 7541 (HPACK) specifications.

## Overview

The compliance test suite validates all major components of HTTP/2:

- **Frame Compliance** (RFC 9113 Section 4.1) - Frame format, parsing, and validation
- **Stream Lifecycle** (RFC 9113 Section 5.1) - Stream state transitions and lifecycle management
- **Flow Control** (RFC 9113 Section 6.9) - Window management and flow control algorithms
- **HPACK** (RFC 7541) - Header compression and table management
- **Priority** (RFC 9113 Section 5.3) - Priority tree management and scheduling
- **Connection Management** (RFC 9113) - Connection establishment and lifecycle

## Test Structure

```
spec/compliance/
├── README.md                           # This file
├── compliance_test_runner.cr           # Main test runner
├── frame_compliance_spec.cr            # Frame format and parsing tests
├── stream_lifecycle_spec.cr            # Stream state and lifecycle tests
├── flow_control_spec.cr                # Flow control and window management tests
├── hpack_compliance_spec.cr            # HPACK compression tests
├── priority_compliance_spec.cr         # Priority and dependency tests
└── connection_compliance_spec.cr       # Connection management tests
```

## Running the Tests

### Quick Start

```bash
# Run all compliance tests
crystal run spec/compliance/compliance_test_runner.cr all

# Quick compliance check (critical areas only)
crystal run spec/compliance/compliance_test_runner.cr quick

# Run specific test categories
crystal run spec/compliance/compliance_test_runner.cr frame
crystal run spec/compliance/compliance_test_runner.cr stream
crystal run spec/compliance/compliance_test_runner.cr flow
crystal run spec/compliance/compliance_test_runner.cr hpack
crystal run spec/compliance/compliance_test_runner.cr priority
crystal run spec/compliance/compliance_test_runner.cr connection
```

### Using Crystal Spec

```bash
# Run individual test files
crystal spec spec/compliance/frame_compliance_spec.cr
crystal spec spec/compliance/stream_lifecycle_spec.cr
crystal spec spec/compliance/flow_control_spec.cr
crystal spec spec/compliance/hpack_compliance_spec.cr
crystal spec spec/compliance/priority_compliance_spec.cr
crystal spec spec/compliance/connection_compliance_spec.cr

# Run all compliance tests
crystal spec spec/compliance/
```

## Test Categories

### 1. Frame Compliance (RFC 9113 Section 4.1)

Validates HTTP/2 frame format, parsing, and validation:

- **Frame Header Format** - Length, type, flags, and stream identifier fields
- **DATA Frame** - Payload validation, padding, END_STREAM flag
- **HEADERS Frame** - Header block fragments, priority, END_HEADERS flag
- **PRIORITY Frame** - Stream dependencies and weights
- **RST_STREAM Frame** - Error codes and stream termination
- **SETTINGS Frame** - Connection parameters and acknowledgment
- **PUSH_PROMISE Frame** - Server push and promised streams
- **PING Frame** - Connection health checks
- **GOAWAY Frame** - Connection termination
- **WINDOW_UPDATE Frame** - Flow control window updates
- **CONTINUATION Frame** - Header block continuation

**Key Validations:**
- Frame size limits (2^14 - 1 octets)
- Stream identifier ranges (31-bit integers)
- Frame type validation
- Flag combinations
- Payload size requirements

### 2. Stream Lifecycle (RFC 9113 Section 5.1)

Tests stream state transitions and lifecycle management:

- **Stream States** - idle, reserved, open, half-closed, closed
- **State Transitions** - Valid and invalid state changes
- **Stream Identifiers** - Client/server stream numbering
- **Concurrency Limits** - SETTINGS_MAX_CONCURRENT_STREAMS
- **Stream Cleanup** - Resource management and cleanup

**Key Validations:**
- All streams start in "idle" state
- Valid state transition sequences
- Stream identifier sequencing
- Concurrency limit enforcement
- Resource cleanup on stream closure

### 3. Flow Control (RFC 9113 Section 6.9)

Validates flow control mechanisms:

- **Flow Control Principles** - Hop-by-hop flow control
- **Window Management** - Connection and stream-level windows
- **WINDOW_UPDATE Frame** - Window size increments
- **Flow Control Algorithms** - Window update calculations
- **Error Handling** - FLOW_CONTROL_ERROR scenarios

**Key Validations:**
- Initial window size (65,535 octets)
- Window size limits (2^31-1 octets)
- Window update range (1 to 2^31-1)
- Flow control applies only to DATA frames
- Window overflow prevention

### 4. HPACK (RFC 7541)

Tests header compression and table management:

- **HPACK Principles** - Compression format validation
- **Indexing** - Static and dynamic table indexing
- **Literal Representations** - Incremental, no-index, never-indexed
- **Dynamic Table Management** - Size updates and eviction
- **Encoding/Decoding** - Header list compression

**Key Validations:**
- Static table entries (61 predefined headers)
- Dynamic table size limits
- Entry eviction algorithms
- Header name/value validation
- Security considerations (never-indexed headers)

### 5. Priority (RFC 9113 Section 5.3)

Validates stream priority and dependency management:

- **Stream Dependencies** - Parent-child relationships
- **Priority Weights** - Weight range (1 to 256)
- **Priority Tree Management** - Tree structure maintenance
- **Priority Scheduling** - Round-robin and weight-based scheduling
- **Priority Frame Processing** - PRIORITY frame handling

**Key Validations:**
- Default weight (16)
- Exclusive and non-exclusive dependencies
- Circular dependency prevention
- Tree rebalancing on dependency changes
- Priority inheritance rules

### 6. Connection Management (RFC 9113)

Tests connection establishment and lifecycle:

- **Connection Establishment** - HTTP/1.1 upgrade mechanism
- **Connection Preface** - "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
- **Settings Negotiation** - Initial settings and acknowledgment
- **Connection State Management** - State transitions
- **Error Handling** - Protocol errors and GOAWAY frames

**Key Validations:**
- Connection preface format
- Settings synchronization
- State transition validation
- Error code handling
- Connection lifecycle events

## Compliance Levels

The test suite categorizes compliance into five levels:

- **FULLY_COMPLIANT** (95-100%) - All requirements met
- **MOSTLY_COMPLIANT** (80-94%) - Minor issues, fully functional
- **PARTIALLY_COMPLIANT** (60-79%) - Some functionality missing
- **NON_COMPLIANT** (1-59%) - Major issues, not functional
- **NOT_IMPLEMENTED** (0%) - Feature not implemented

## Test Reports

The compliance test runner generates detailed reports:

- **Console Output** - Real-time test results and summaries
- **Markdown Report** - Detailed compliance report with issues and recommendations
- **Compliance Checklist** - RFC 9113 requirement checklist

### Sample Report Structure

```markdown
# HTTP/2 RFC 9113 Compliance Report

## Executive Summary
- Total Tests: 259
- Passed: 237
- Overall Success Rate: 91.5%

## Detailed Results

### Frame Compliance
- RFC Section: RFC 9113 Section 4.1
- Compliance Level: MOSTLY_COMPLIANT
- Success Rate: 93.3%
- Tests: 42/45 passed

#### Issues
- Frame size validation needs improvement
- Unknown frame type handling incomplete

#### Recommendations
- Implement strict frame size validation
- Add comprehensive unknown frame type handling
```

## Integration with External Tools

### h2spec Integration

The compliance tests complement external validation tools:

```bash
# Install h2spec
go install github.com/summerwind/h2spec/cmd/h2spec@latest

# Run h2spec against your server
h2spec -p 8080

# Run specific test cases
h2spec -p 8080 -t 4.1  # Frame format tests
h2spec -p 8080 -t 5.1  # Stream lifecycle tests
```

### Performance Testing

Combine compliance tests with performance validation:

```bash
# Run compliance tests
crystal run spec/compliance/compliance_test_runner.cr all

# Run performance benchmarks
crystal run spec/performance/benchmark_suite.cr

# Run stress tests
crystal run spec/stress/stress_test_suite.cr
```

## Continuous Integration

Add compliance tests to your CI pipeline:

```yaml
# .github/workflows/compliance.yml
name: HTTP/2 Compliance Tests

on: [push, pull_request]

jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: crystal-lang/install-crystal@v1
      - run: crystal spec spec/compliance/
      - run: crystal run spec/compliance/compliance_test_runner.cr all
```

## Troubleshooting

### Common Issues

1. **Test Failures Due to Missing Implementation**
   - Check if the required classes and methods exist
   - Implement missing functionality before running tests

2. **Performance Issues**
   - Some tests may be slow due to large data sets
   - Use `--release` flag for better performance: `crystal run --release spec/compliance/compliance_test_runner.cr all`

3. **Memory Issues**
   - Large test suites may require more memory
   - Increase heap size: `CRYSTAL_OPTS="--max-heap-size=1GB" crystal run spec/compliance/compliance_test_runner.cr all`

### Debugging

Enable verbose output for debugging:

```bash
# Run with verbose output
crystal spec spec/compliance/ --verbose

# Run specific failing test
crystal spec spec/compliance/frame_compliance_spec.cr:42 --verbose
```

## Contributing

When adding new compliance tests:

1. **Follow RFC Specifications** - Ensure tests match exact RFC requirements
2. **Add Comprehensive Coverage** - Test both valid and invalid scenarios
3. **Include Edge Cases** - Test boundary conditions and error cases
4. **Document Test Purpose** - Add clear comments explaining what each test validates
5. **Update Test Runner** - Add new test categories to the compliance test runner

### Test Writing Guidelines

```crystal
describe "Feature Name (RFC Section)" do
  it "validates specific requirement" do
    # RFC reference comment
    # RFC 9113 Section X.Y: Specific requirement
    
    # Test implementation
    result = test_specific_requirement
    
    # Assertions
    result.should be_true
  end
end
```

## References

- [RFC 9113 - HTTP/2](https://datatracker.ietf.org/doc/html/rfc9113)
- [RFC 7541 - HPACK](https://datatracker.ietf.org/doc/html/rfc7541)
- [HTTP/2 Specification](https://httpwg.org/specs/rfc9113.html)
- [h2spec Tool](https://github.com/summerwind/h2spec)

## License

This test suite is part of the Duo HTTP/2 implementation and follows the same license terms.
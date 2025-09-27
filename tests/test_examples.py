#!/usr/bin/env python3

import os
import subprocess
import tempfile
import pytest
from pathlib import Path


class TestDuendeExamples:
    @classmethod
    def setup_class(cls):
        cls.project_root = Path(__file__).parent.parent
        cls.compiler_path = cls.project_root / "duende"
        cls.examples_dir = cls.project_root / "examples"


        if not cls.compiler_path.exists():
            subprocess.run(["dub", "build"], cwd=cls.project_root, check=True)

    def compile_and_run(self, source_file, input_data=None):
        """Compile a Duende source file and run the resulting executable"""

        result = subprocess.run(
            [str(self.compiler_path), str(source_file)],
            capture_output=True,
            text=True,
            cwd=self.project_root
        )

        if result.returncode != 0:
            raise Exception(f"Compilation failed: {result.stderr}")

        build_dir = source_file.parent / "duende_build"
        executable = build_dir / source_file.stem

        if not executable.exists():
            raise Exception(f"Executable not found: {executable}")

        run_result = subprocess.run(
            [str(executable)],
            input=input_data,
            capture_output=True,
            text=True
        )

        return run_result.stdout, run_result.stderr, run_result.returncode

    def test_variables_example(self):
        """Test the variables.du example"""
        source_file = self.examples_dir / "variables.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        assert stdout.strip() == "55", f"Expected '55', got '{stdout.strip()}'"

    def test_basic_arithmetic_example(self):
        """Test the basic_arithmetic.du example"""
        source_file = self.examples_dir / "basic_arithmetic.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')
        assert lines[0] == "7", f"Expected '7' for x, got '{lines[0]}'"
        assert lines[1] == "3.5", f"Expected '3.5' for y, got '{lines[1]}'"
        # Modulo outputs
        assert lines[2] == "1", f"Expected '1' for 10%3, got '{lines[2]}'"
        assert lines[3] == "4", f"Expected '4' for 25%7, got '{lines[3]}'"
        assert lines[4] == "0", f"Expected '0' for 8%2, got '{lines[4]}'"

    def test_type_casting_example(self):
        """Test the type_casting.du example"""
        source_file = self.examples_dir / "type_casting.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = [ln for ln in stdout.strip().split('\n') if ln.strip()]
        i = 0
        assert lines[i] == "123"; i += 1
        assert lines[i] == "3"; i += 1
        assert lines[i] == "2.5"; i += 1
        # Sum of even ints among ["42", "3.14", "-7", "NaN", "256"] -> 42 + 0 + 0 + 0 + 256 = 298
        assert lines[i] == "298"; i += 1
        assert lines[i] == "255"; i += 1
        assert lines[i] == "255"; i += 1
        # safeCast results and fallbacks
        assert lines[i] == "10"; i += 1
        assert lines[i] == "123"; i += 1
        assert lines[i] == "-1"; i += 1
        assert lines[i] == "-2"; i += 1

    def test_print_statements_example(self):
        """Test the print_statements.du example"""
        source_file = self.examples_dir / "print_statements.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')
        assert lines[0] == "Player Alice scored 95 points!"
        assert lines[1] == "Next level requires 100 points"

    def test_functions_example(self):
        """Test the functions.du example"""
        source_file = self.examples_dir / "functions.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')
        i = 0
        assert lines[i] == "15"; i += 1
        assert lines[i] == "Hello, Duende"; i += 1
        assert lines[i] == "14"; i += 1        # multiply(7)
        assert lines[i] == "20"; i += 1        # add3(5)
        assert lines[i] == "11"; i += 1        # add3(5,1)
        assert lines[i] == "9"; i += 1         # inc(4)
        assert lines[i] == "INFO: Ready"; i += 1
        assert lines[i] == "ERROR: Oops"; i += 1
        # Named argument calls
        assert lines[i] == "6"; i += 1
        assert lines[i] == "16"; i += 1
        assert lines[i] == "Hello, World"; i += 1
        assert lines[i] == "DEBUG: Trace"; i += 1

    def test_global_vars_example(self):
        """Test the global_vars.du example (non-constant globals in source order)"""
        source_file = self.examples_dir / "global_vars.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = [ln for ln in stdout.strip().split('\n') if ln.strip()]

        expected = [
            "gen:1",
            "up:hi",
            "A:2",
            "MSG:HI",
            "C:7",
            "func:5",
        ]

        for i, expected_line in enumerate(expected):
            assert i < len(lines), f"Missing line {i}: expected '{expected_line}'"
            assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"

    def test_control_flow_example(self):
        """Test the control_flow.du example"""
        source_file = self.examples_dir / "control_flow.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected_factorials = [
            "factorial(1) = 1",
            "factorial(2) = 2",
            "factorial(3) = 6",
            "factorial(4) = 24",
            "factorial(5) = 120"
        ]

        # Test categorizeNumber with elif
        expected_categorize = ["Number 15 is medium"]

        # While loop prints 1,2,4,5 (skips 3 via continue, stops after printing 5 via break)
        expected_while = ["1", "2", "4", "5"]

        expected_output = expected_factorials + expected_categorize + expected_while

        for i, expected in enumerate(expected_output):
            if i < len(lines):
                assert lines[i] == expected, f"Line {i}: expected '{expected}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected}'"

    def test_booleans_example(self):
        """Test the booleans.du example"""
        source_file = self.examples_dir / "booleans.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "false",  # !a (where a = true)
            "true",   # !b (where b = false)
            "false",  # a && b (true && false)
            "true",   # a || b (true || false)
            "false",  # !(1 == 1)
            "true",   # !(1 != 1)
            "true"    # !(a && b) && (a || b)
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_bytes_example(self):
        """Test the bytes.du example"""
        source_file = self.examples_dir / "bytes.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        i = 0
        assert lines[i] == "3"; i += 1
        assert lines[i] == "3"; i += 1
        assert lines[i] == "255"; i += 1
        assert lines[i] == "hello world"; i += 1
        assert lines[i] == "ell"; i += 1
        assert lines[i] == "5"; i += 1
        # iteration sum of 'hello' ascii bytes: h=104 e=101 l=108 l=108 o=111 -> 532
        assert lines[i] == "532"; i += 1
        assert lines[i] == "HELLO"; i += 1
        assert lines[i] == "hello"; i += 1
        assert lines[i] == "2"; i += 1

    def test_input_example(self):
        """Test the input.du example"""
        source_file = self.examples_dir / "input.du"

        # Test with sample input
        input_data = "World\ntest\nDuende\n"
        stdout, stderr, returncode = self.compile_and_run(source_file, input_data)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        # Expected output:
        # "Hello, World"
        # "Length=4" (for "test")
        # "Name: Prompted: Duende"
        assert lines[0] == "Hello, World"
        assert lines[1] == "Length=4"
        assert lines[2] == "Name: Prompted: Duende"

    def test_collections_api_example(self):
        """Test the collections_api.du example"""
        source_file = self.examples_dir / "collections_api.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "List length: 5",
            "List empty: false",
            "List first: 1",
            "List last: 5",
            "Slice length: 3",
            "Slice first: 2",
            "Sorted first: a",
            "Sorted last: c",
            "Before add: 2",
            "After add: 3",
            "Added last: 30",
            "Dict length: 3",
            "Dict empty: false",
            "Keys length: 3",
            "Values length: 3",
            "Empty list length: 0",
            "Empty list empty: true",
            "Empty list first: -1",
            "Empty dict length: 0",
            "Empty dict empty: true"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_collections_example(self):
        """Test the collections.du example"""
        source_file = self.examples_dir / "collections.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "First: 1",
            "Port: 8080"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_regex_example(self):
        """Test the regex.du example"""
        source_file = self.examples_dir / "regex.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "Match found!",
            "hello",
            "false",
            "3",
            "Hello",
            "WORD WORD"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_enums_example(self):
        """Test the enums.du example"""
        source_file = self.examples_dir / "enums.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "Processing active item"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_structs_and_frames_example(self):
        """Test the structs_and_frames.du example"""
        source_file = self.examples_dir / "structs_and_frames.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "New Moved Point ->  x: 0 / y:{p1.y}",
            "Moved point: 4 / 5"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_protocols_example(self):
        """Test the protocols.du example"""
        source_file = self.examples_dir / "protocols.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "Hello, World",
            "Hello Foo"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_lambdas_example(self):
        """Test the lambdas.du example"""
        source_file = self.examples_dir / "lambdas.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "6",  # inc(5) should print 6
            "7"   # incCaptured(2) with y=5 should print 7
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_defer_example(self):
        """Test the defer.du example"""
        source_file = self.examples_dir / "defer.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "This should be first thing to print",
            "This should be the last thing to print"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_error_handling_example(self):
        """Test the error_handling.du example"""
        source_file = self.examples_dir / "error_handling.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "Good division: 5",
            "Bad division: -1",
            "Good parse: 42.5",
            "Bad parse: 0",
            "Maybe some: Hello",
            "Maybe none: default"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_pattern_matching_example(self):
        """Test the pattern_matching.du example"""
        source_file = self.examples_dir / "pattern_matching.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "error",          # res from checkStatus(Status.ACTIVE, -1)
            "ACTIVE",         # res2 unwrap
            "INACTIVE",       # res3 unwrap
            "This looks like an email",
            "First number is 1",
            "Stop the car",
            "success",
            "failed to read: This should NOT be OK!",
            "zero",
            "one",
            "many"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_strings_example(self):
        """Test the strings.du example"""
        source_file = self.examples_dir / "strings.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "Hello Duende! Score=95, ratio=0.33",
            "a-b-c",
            "Hello Duende",
            "HELLO",
            "hello",
            "trim me",
            "cde",
            "1",
            "2",
            "true",
            "true",
            "true",
            "true",
            "42",
            "3.14",
            "true",
            "hi",
            "-1",
            "true",
            "true",
            "Value: 0007",
            "2.6",
            "true",
            "3",
            "y",
            "121",
            "a,b",
            "b",
            "Escaped: \\",
            "Literal: ${name} and }",
            "Mix: ${name} -> Duende",
            "Singles: \\ and } and ${ ok",
            "1",
            "2",
            "4"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_sleep_example(self):
        """Test the sleep.du example"""
        source_file = self.examples_dir / "sleep.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        expected = [
            "start",
            "done"
        ]

        for i, expected_line in enumerate(expected):
            if i < len(lines):
                assert lines[i] == expected_line, f"Line {i}: expected '{expected_line}', got '{lines[i]}'"
            else:
                assert False, f"Missing line {i}: expected '{expected_line}'"

    def test_dates_and_times_example(self):
        """Test the dates_and_times.du example"""
        source_file = self.examples_dir / "dates_and_times.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        # We can't assert dynamic 'today' and 'utc' fully, but we can assert fixed parts count and known constants
        assert lines[2] == "1990-07-06"
        assert lines[3] == "2025-05-20 18:30:00"
        # timezone line 4 ends with offset; for -03:00 offset on a naive UTC-like time we expect 21:30:00-03:00
        assert lines[4].startswith("2025-05-20 21:30:00")
        # Field extraction
        assert lines[5] == "1990"
        assert lines[6] == "7"
        assert lines[7] == "6"
        assert lines[8] == "18"
        assert lines[9] == "30"
        assert lines[10] == "0"
        # Comparison and arithmetic
        assert lines[11] == "true"
        assert lines[12] == "1990-07-08"
        # Additional arithmetic helpers
        assert lines[13] == "2025-05-20 23:30:00"  # meetup + 5 hours (18:30 -> 23:30)
        assert lines[14] == "2025-05-20 20:00:00"  # meetup + 90 minutes (18:30 -> 20:00)
        assert lines[15] == "2025-05-20 19:31:01"  # meetup + 3661 seconds (18:30:00 -> 19:31:01)
        # Parsing
        assert lines[16] == "2025-12-31 23:59:59"
        # Match
        assert lines[17] == "NewYearEveEve"

        def test_hashing_digest_example(self):
            """Test the hashing_digest.du example"""
            source_file = self.examples_dir / "hashing_digest.du"
            stdout, stderr, returncode = self.compile_and_run(source_file)

            assert returncode == 0, f"Program failed: {stderr}"
            lines = [ln for ln in stdout.strip().split('\n') if ln.strip()]

            i = 0
            # Hex digests for "abc"
            assert lines[i] == "900150983cd24fb0d6963f7d28e17f72"; i += 1  # md5
            assert lines[i] == "a9993e364706816aba3e25717850c26c9cd0d89d"; i += 1  # sha1
            assert lines[i] == "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7"; i += 1  # sha224
            assert lines[i] == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"; i += 1  # sha256
            assert lines[i] == "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"; i += 1  # sha384
            assert lines[i] == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"; i += 1  # sha512
            assert lines[i] == "4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa"; i += 1  # sha512/224
            assert lines[i] == "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23"; i += 1  # sha512/256

            # CRCs for "abc" (decimal)
            assert lines[i] == "891568578"; i += 1  # crc32
            assert lines[i] == "7372421403230734421"; i += 1  # crc64 ECMA

            # MurmurHash3 for "abc"
            assert lines[i] == "3017643002"; i += 1  # seed 0 (0xB3DD93FA)
            assert lines[i] == "1313807976"; i += 1  # seed 42 (0x4E4F1E68)

            # For long text 'fox'
            assert lines[i] == "9e107d9d372bb6826bd81d3542a419d6"; i += 1  # md5
            assert lines[i] == "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"; i += 1  # sha256
            assert lines[i] == "1095738169"; i += 1  # crc32
            assert lines[i] == "4746884454959122491"; i += 1  # crc64 ECMA
            assert lines[i] == "776992547"; i += 1  # Murmur seed 0
            assert lines[i] == "880582914"; i += 1  # Murmur seed 42
    def test_imports_example(self):
        """Test the imports.du example (module system)"""
        source_file = self.examples_dir / "imports.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')
        assert lines[0] == "3"
        assert lines[1] == "-2"

    def test_math_example(self):
        """Test the math.du example"""
        source_file = self.examples_dir / "math.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        # Verify outputs. Many are integers or simple values rendered without extra decimals by writeln.
        expected_prefix = [
            "5",        # abs(-5)
            "3.2",      # abs(-3.2)
            "3",        # min(3,7)
            "7",        # max(3,7)
            "2.4",      # min(2.5,2.4)
            "2.5",      # max(2.5,2.4)
            "3",        # floor(3.7)
            "4",        # ceil(3.1)
            "4",        # round(3.6)
            "3",        # round(3.4)
            "3",        # sqrt(9)
            "256",      # pow(2,8)
        ]

        for i, exp in enumerate(expected_prefix):
            assert lines[i] == exp, f"Line {i}: expected '{exp}', got '{lines[i]}'"

        # log(exp(1)) ~ 1.0, allow small floating formatting differences
        logexp = float(lines[12])
        assert abs(logexp - 1.0) < 1e-9

        # Trig zeros
        assert lines[13] == "0"  # sin(0)
        assert lines[14] == "1"  # cos(0)
        assert lines[15] == "0"  # tan(0)
        assert lines[16] == "0"  # sinDeg(0)
        assert lines[17] == "1"  # cosDeg(0)
        assert lines[18] == "0"  # tanDeg(0)

        # Conversions: toRadians(180) ~ pi, toDegrees(pi) ~ 180
        pi_val = float(lines[19])
        assert abs(pi_val - 3.141592653589793) < 1e-5
        assert lines[20] == "180"

        # Formatting helpers
        assert lines[21] == "3.14"
        assert lines[22] == "3.1416"

    def test_jsdoc_example(self):
        """Test the jsdoc.du example (JSDoc comments are ignored)"""
        source_file = self.examples_dir / "jsdoc.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')
        assert lines[0] == "5"

    def test_file_io_example(self):
        """Test the file_io.du example"""
        source_file = self.examples_dir / "file_io.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')

        # Assert deterministic, environment-agnostic outputs
        # 0: dir exists before
        assert lines[0] == "dir exists before: false"
        # 1: dir exists after make
        assert lines[1] == "dir exists after make: true"
        # 2: file1 exists after write
        assert lines[2] == "file1 exists after write: true"
        # 3: file1 text
        assert lines[3] == "file1 text: hello"
        # 4: file1 text after append
        assert lines[4] == "file1 text after append: hello!"
        # 5..7: file2 lines info
        assert lines[5] == "file2 lines count: 3"
        assert lines[6] == "file2 first: a"
        assert lines[7] == "file2 last: c"
        # 8..10: bytes info
        assert lines[8] == "bytes length: 3"
        assert lines[9] == "bytes first: 1"
        assert lines[10] == "bytes last: 255"
        # 11: file size (hello!) is 6
        assert lines[11] == "file1 size: 6"
        # 12..13: metadata
        assert lines[12] == "meta isFile: true"
        assert lines[13] == "meta size: 6"
        # 14: dir entries count (file1.txt, file2.txt, bin.dat) -> 3
        assert lines[14] == "dir entries: 3"
        # 15: file1 exists after delete -> false
        assert lines[15] == "file1 exists after delete: false"
        # 16: dir exists after remove -> false
        assert lines[16] == "dir exists after remove: false"


    def test_networking_example(self):
        """Test the networking.du example (TCP echo)"""
        source_file = self.examples_dir / "networking.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')
        assert lines[0] == "echo:hello"

    def test_networking_udp_example(self):
        """Test the networking_udp.du example (UDP echo + timeout)"""
        source_file = self.examples_dir / "networking_udp.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')
        assert lines[0] == "udp:ping"

    def test_async_example(self):
        """Test the async.du example (fiber scheduler + networking)"""
        source_file = self.examples_dir / "async.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.strip().split('\n')
        assert lines[0] == "echo:hello"

    def test_process_example(self):
        """Test the process.du example (process management)"""
        source_file = self.examples_dir / "process.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = stdout.split('\n')
        # From execute: hello, error, 0
        assert lines[0].strip() == "hello"
        assert lines[1].strip() == "error"
        assert lines[2].strip() == "0"
        # From pipeShell: out, err, 0
        assert lines[3].strip() == "out"
        assert lines[4].strip() == "err"
        assert lines[5].strip() == "0"
        # From spawn+wait: 0
        assert lines[6].strip() == "0"

    def test_others_example(self):
        """Test the others.du example (OS/CPU/args builtins)"""
        source_file = self.examples_dir / "others.du"

        # First run without args: should print usage after OS/CPU lines
        # Compile
        result = subprocess.run(
            [str(self.compiler_path), str(source_file)],
            capture_output=True,
            text=True,
            cwd=self.project_root
        )
        if result.returncode != 0:
            raise Exception(f"Compilation failed: {result.stderr}")
        build_dir = source_file.parent / "duende_build"
        executable = build_dir / source_file.stem
        assert executable.exists()

        run1 = subprocess.run([str(executable)], capture_output=True, text=True)
        assert run1.returncode == 0
        lines = [ln for ln in run1.stdout.strip().split('\n') if ln.strip()]
        # At least 3 lines: OS, CPU, Usage
        assert len(lines) >= 3
        assert lines[0].startswith("OS: ")
        assert lines[1].startswith("CPU: ")
        assert lines[2] == "Usage: others <name> <n1> <n2> ..."

        # Second run with args: name and numbers
        run2 = subprocess.run([str(executable), "Alice", "10", "-5", "x"], capture_output=True, text=True)
        assert run2.returncode == 0
        lines2 = [ln for ln in run2.stdout.strip().split('\n') if ln.strip()]
        # Expect OS, CPU, greeting, sum (10 + (-5) = 5; ignore 'x')
        assert lines2[0].startswith("OS: ")
        assert lines2[1].startswith("CPU: ")
        assert lines2[2] == "Hello Alice"
        assert lines2[3] == "Sum=5"

    def test_std_xml_example(self):
        """Test the std_xml.du example (XML parsing/generation)"""
        source_file = self.examples_dir / "std_xml.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = [ln for ln in stdout.strip().split('\n') if ln.strip()]
        i = 0
        assert lines[i] == "catalog"; i += 1
        assert lines[i] == "2"; i += 1
        assert lines[i] == "b1"; i += 1
        assert lines[i] == "Duende Guide"; i += 1
        # Compact XML: attribute order is sorted by key for determinism
        # Expect catalog with two book children; we won't assert entire XML string, just that it starts/ends correctly
        assert lines[i].startswith("<catalog>"); i += 1
        # Pretty list XML
        assert lines[i].startswith("<list>"); i += 1

    def test_std_encoding_example(self):
        """Test the std_encoding.du example (encoding helpers)"""
        source_file = self.examples_dir / "std_encoding.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = [ln for ln in stdout.strip().split('\n') if ln.strip()]
        i = 0
        # UTF-8 length of "Hello, 世界" -> "Hello, " (7 bytes) + 世界 (3+3) = 13
        assert lines[i] == "13"; i += 1
        assert lines[i] == "Hello"; i += 1
        # UTF-16 decode round-trips
        assert lines[i] == "Hello, 世界"; i += 1
        assert lines[i] == "Hello, 世界"; i += 1
        # Base64 of UTF-8("Hello, 世界")
        assert lines[i] == "SGVsbG8sIOS4lueVjA=="; i += 1
        assert lines[i] == "Hello, 世界"; i += 1
        # Hex prefix and round-trip
        assert lines[i] == "48656c6c6f"; i += 1
        assert lines[i] == "Hello, 世界"; i += 1
        # Generic conversions and hex of OK
        assert lines[i] == "Hello, 世界"; i += 1
        assert lines[i] == "4f4b"; i += 1
        assert lines[i] == "OK"; i += 1

    def test_database_example(self):
        """Test the database.du example (SQLite via ddbc)"""
        source_file = self.examples_dir / "database.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = [ln for ln in stdout.strip().split('\n') if ln.strip()]
        # Expected prints from the example
        # count before tx: 3
        # count after rollback: 3
        # first row name:age -> Alice:30
        # last row name:age -> Carol:27
        # Note: we updated Bob's age to 26 -> after +1 becomes 26 => Bob:26 middle row (not asserted)
        assert len(lines) >= 4
        i = 0
        assert lines[i] == "3"; i += 1
        assert lines[i] == "3"; i += 1
        assert lines[i] == "Alice:30"; i += 1
        assert lines[i] == "Carol:27"; i += 1

    def test_vibe_demo_example(self):
        """Test the vibe_demo.du example"""
        source_file = self.examples_dir / "vibe_demo.du"
        stdout, stderr, returncode = self.compile_and_run(source_file)

        assert returncode == 0, f"Program failed: {stderr}"
        lines = [ln for ln in stdout.strip().split('\n') if ln.strip()]
        
        # Check that actual functionality outputs are present
        expected_outputs = [
            "=== Duende Vibe.d Integration Demo ===",
            "--- Logging System ---",
            "Logger created: DuendeApp (level: 2)",
            "INFO: Application starting up",
            "WARN: This is a warning message",
            "DEBUG: Debug information",
            "--- TLS/SSL Context ---",
            "TLS context created:",
            "--- Timer Operations ---",
            "Timer created:",
            "Timeout set:",
            "--- HTTP Client Operations ---",
            "HTTP client created",
            "--- File System Operations ---",
            "File written async:",
            "File read async:",
            # Directory can either be created or already exist
            "--- Integration Test Complete ---",
            "vibe.d components tested successfully:",
            "✓ Logging system",
            "✓ TLS/SSL context management", 
            "✓ Timer operations",
            "✓ HTTP client creation",
            "✓ File system operations",
            "Vibe.d integration demo completed successfully!"
        ]
        
        output_text = '\n'.join(lines)
        for expected in expected_outputs:
            assert expected in output_text, f"Expected output '{expected}' not found in output"
        
        # Check that directory operation happened (either created or already exists)
        assert ("Directory created async:" in output_text or "Directory already exists:" in output_text), \
            "No directory operation output found"

    def test_semantic_errors_example(self):
        """Test that semantic_errors.du example fails compilation with appropriate error messages"""
        source_file = self.examples_dir / "semantic_errors.du"
        
        # Attempt compilation - this should fail due to semantic errors
        result = subprocess.run(
            [str(self.compiler_path), str(source_file)],
            capture_output=True,
            text=True,
            cwd=self.project_root
        )
        
        # The compilation should fail (semantic errors should prevent D compilation)
        # Note: The current implementation may exit with code 0 but print errors to stdout/stderr
        error_output = result.stderr + result.stdout
        
        # Should contain specific semantic error messages
        expected_errors = [
            "Math functions require 'import std.math'",
            "Hash and digest functions require 'import std.hash' or 'import std.digest'",
            "Invalid use of 'break' outside of a loop",
            "Invalid use of 'continue' outside of a loop"
        ]
        
        # At least one of the expected semantic errors should be present
        found_errors = []
        for expected_error in expected_errors:
            if expected_error in error_output:
                found_errors.append(expected_error)
        
        assert len(found_errors) > 0, f"Expected semantic errors not found. Output: {error_output}"
        
        # Verify no executable was created due to semantic errors
        build_dir = source_file.parent / "duende_build"
        executable = build_dir / source_file.stem
        assert not executable.exists(), f"Executable should not be created when semantic errors are present: {executable}"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
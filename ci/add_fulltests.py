"""Adds the full UI test target to project.yml for the full-test workflow only."""
s = open("project.yml").read()
s = s.replace("    scheme: {}\n", "    scheme:\n      testTargets: [MedJarsFullUITests]\n", 1)
s += """  MedJarsFullUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: ci/FullUITests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.medjars.app.fulluitests
        TEST_TARGET_NAME: MedJars
        GENERATE_INFOPLIST_FILE: YES
        SWIFT_VERSION: "5.0"
    dependencies:
      - target: MedJars
"""
open("project.yml", "w").write(s)

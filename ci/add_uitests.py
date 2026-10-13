"""Adds a UI test target to project.yml for the crash reproduction workflow only."""
s = open("project.yml").read()
s = s.replace("    scheme: {}\n", "    scheme:\n      testTargets: [MedJarsUITests]\n", 1)
s += """  MedJarsUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: ci/UITests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.medjars.app.uitests
        TEST_TARGET_NAME: MedJars
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: MedJars
"""
open("project.yml", "w").write(s)

from pathlib import Path
import re
import stat
import unittest


ROOT = Path(__file__).resolve().parents[1]
PKG_DIR = ROOT / "openwrt" / "homebox"
WORKFLOW = ROOT / ".github" / "workflows" / "openwrt-apk.yml"
BUILD_SCRIPT = ROOT / "openwrt" / "scripts" / "build-apk-in-sdk.sh"
DOCKER_SCRIPT = ROOT / "openwrt" / "scripts" / "build-apk-docker.sh"


class OpenWrtPackageTests(unittest.TestCase):
    def test_package_makefile_targets_openwrt_sdk_apk_builds(self) -> None:
        makefile = (PKG_DIR / "Makefile").read_text()

        self.assertIn("include $(TOPDIR)/rules.mk", makefile)
        self.assertIn("$(eval $(call BuildPackage,homebox))", makefile)
        self.assertIn("USERID:=homebox:homebox", makefile)
        self.assertIn("DEPENDS:=+libgcc", makefile)
        self.assertIn("HOMEBOX_PREBUILT", makefile)
        self.assertNotIn("rust-package.mk", makefile)
        self.assertNotIn("PKG_BUILD_DEPENDS:=node/host rust/host", makefile)
        self.assertRegex(makefile, r"\$\(INSTALL_BIN\).*\$\(PKG_BUILD_DIR\)/homebox.*\$\(1\)/usr/bin/")

    def test_package_uses_prebuilt_binary_without_sdk_rust_compile(self) -> None:
        makefile = (PKG_DIR / "Makefile").read_text()

        build_prepare = re.search(
            r"define Build/Prepare\n(?P<body>.*?)\nendef",
            makefile,
            flags=re.S,
        )
        self.assertIsNotNone(build_prepare)
        body = build_prepare.group("body")
        self.assertIn("HOMEBOX_PREBUILT must point to a prebuilt homebox binary", body)
        self.assertIn("$(INSTALL_BIN)", body)
        self.assertIn("$(PKG_BUILD_DIR)/homebox", body)
        self.assertNotIn("cargo", makefile)
        self.assertNotIn("pnpm", makefile)

    def test_procd_init_maps_uci_to_homebox_serve(self) -> None:
        init_file = PKG_DIR / "files" / "homebox.init"
        init_text = init_file.read_text()
        mode = init_file.stat().st_mode

        self.assertTrue(mode & stat.S_IXUSR)
        self.assertIn("#!/bin/sh /etc/rc.common", init_text)
        self.assertIn("USE_PROCD=1", init_text)
        self.assertIn("PROG=\"/usr/bin/homebox\"", init_text)
        self.assertIn("procd_append_param command serve", init_text)
        self.assertIn("append_arg \"$section\" host \"--host\"", init_text)
        self.assertIn("append_arg \"$section\" port \"--port\"", init_text)
        self.assertIn("append_arg \"$section\" workers \"--workers\"", init_text)
        self.assertIn("append_arg \"$section\" max_connections \"--max-connections\"", init_text)
        self.assertIn("append_arg \"$section\" keep_alive_secs \"--keep-alive-secs\"", init_text)
        self.assertIn("procd_set_param respawn", init_text)
        self.assertIn("procd_set_param user homebox", init_text)
        self.assertIn('procd_add_reload_trigger "homebox"', init_text)

    def test_default_config_is_enabled_on_lan_port_3300(self) -> None:
        config = (PKG_DIR / "files" / "homebox.config").read_text()

        self.assertIn("config homebox 'main'", config)
        self.assertIn("option enabled '1'", config)
        self.assertIn("option host '0.0.0.0'", config)
        self.assertIn("option port '3300'", config)
        self.assertIn("option respawn '1'", config)

    def test_firewall_user_include_opens_lan_tcp_port(self) -> None:
        firewall = (PKG_DIR / "files" / "homebox.firewall").read_text()

        self.assertIn("HOMEBOX_PORT", firewall)
        self.assertIn("iptables", firewall)
        self.assertIn("nft", firewall)
        self.assertIn("3300", firewall)
        self.assertIn("HOMEBOX_OPEN_FIREWALL", firewall)

    def test_docs_describe_openwrt_25_apk_build_and_install(self) -> None:
        docs = (ROOT / "openwrt" / "README.md").read_text()

        self.assertIn("OpenWrt 25.12", docs)
        self.assertIn(".apk", docs)
        self.assertIn("HOMEBOX_PREBUILT", docs)
        self.assertIn("package/homebox", docs)
        self.assertIn("make package/homebox/compile", docs)
        self.assertIn("apk add", docs)
        self.assertIn("/etc/config/homebox", docs)

    def test_sdk_build_script_cross_compiles_binary_and_packages_apk(self) -> None:
        script = BUILD_SCRIPT.read_text()
        mode = BUILD_SCRIPT.stat().st_mode

        self.assertTrue(mode & stat.S_IXUSR)
        self.assertIn("OPENWRT_VERSION", script)
        self.assertIn("TARGET", script)
        self.assertIn("SUBTARGET", script)
        self.assertIn("SDK_CACHE_DIR", script)
        self.assertIn("downloads.openwrt.org/releases", script)
        self.assertIn("openwrt-sdk-${OPENWRT_VERSION}", script)
        self.assertIn("package/homebox", script)
        self.assertIn("SOURCE_ROOT", script)
        self.assertIn("--exclude web/node_modules", script)
        self.assertIn("--exclude server/target", script)
        self.assertIn("SKIP_WEB_BUILD", script)
        self.assertIn("Using existing frontend build", script)
        self.assertIn("SDK_EXTRACTED_DIR", script)
        self.assertIn("OPENWRT_FORCE_PREREQ", script)
        self.assertIn("PKG_RELEASE", script)
        self.assertIn("openwrt_release_suffix", script)
        self.assertIn("tr '[:lower:]' '[:upper:]'", script)
        self.assertNotIn("${target_env_suffix^^}", script)
        self.assertNotIn("rsync", script)
        self.assertIn("rustup target add", script)
        self.assertIn("x86_64-unknown-linux-musl", script)
        self.assertIn("aarch64-unknown-linux-musl", script)
        self.assertIn("armv7-unknown-linux-musleabihf", script)
        self.assertIn("HOMEBOX_ENV=production", script)
        self.assertIn("HOMEBOX_PREBUILT", script)
        self.assertNotIn("scripts/feeds install", script)
        self.assertIn("CONFIG_PACKAGE_homebox=m", script)
        self.assertIn("OPENWRT_BUILD_JOBS", script)
        self.assertIn("detected_jobs > 4", script)
        self.assertIn("package/homebox/compile", script)
        self.assertIn("*.apk", script)

    def test_docker_wrapper_runs_linux_sdk_builder_from_non_linux_hosts(self) -> None:
        script = DOCKER_SCRIPT.read_text()
        mode = DOCKER_SCRIPT.stat().st_mode

        self.assertTrue(mode & stat.S_IXUSR)
        self.assertIn("node:22-bookworm-slim", script)
        self.assertIn("--platform", script)
        self.assertIn("linux/amd64", script)
        self.assertIn("WORK_DIR=/tmp/homebox-openwrt", script)
        self.assertIn("SDK_CACHE_DIR=/work/openwrt/.cache", script)
        self.assertIn("OPENWRT_BUILD_JOBS", script)
        self.assertIn("--no-install-recommends", script)
        self.assertIn("gawk", script)
        self.assertIn("rsync", script)
        self.assertIn("python3-setuptools", script)
        self.assertNotIn("nodejs", script)
        self.assertNotIn("npm \\", script)
        self.assertIn("openwrt/scripts/build-apk-in-sdk.sh", script)
        self.assertIn("OPENWRT_VERSION", script)
        self.assertIn("TARGET", script)
        self.assertIn("SUBTARGET", script)
        self.assertIn("SOURCE_VERSION", script)
        self.assertIn("RUST_TOOLCHAIN", script)
        self.assertIn("RUST_TARGET", script)
        self.assertIn("SKIP_WEB_BUILD", script)
        self.assertIn("INSTALL_BUILD_DEPS", script)
        self.assertIn("OPENWRT_FORCE_PREREQ", script)
        self.assertIn("Acquire::Retries=5", script)

    def test_github_workflow_builds_common_openwrt_25_apk_targets(self) -> None:
        workflow = WORKFLOW.read_text()

        self.assertIn("name: OpenWrt APK", workflow)
        self.assertIn("workflow_dispatch", workflow)
        self.assertIn("OPENWRT_VERSION", workflow)
        self.assertIn("25.12.4", workflow)
        self.assertIn("build-apk-in-sdk.sh", workflow)
        self.assertIn("WORK_DIR: $RUNNER_TEMP/homebox-openwrt", workflow)
        self.assertNotIn("WORK_DIR: ${{ runner.temp }}", workflow)
        self.assertIn("gawk", workflow)
        self.assertIn("rsync", workflow)
        self.assertIn("python3-setuptools", workflow)
        self.assertIn("actions/upload-artifact@v4", workflow)
        self.assertIn("homebox-apk-${{ matrix.target }}-${{ matrix.subtarget }}", workflow)
        self.assertRegex(workflow, r"branches:\n\s+- main\n")

        common_targets = [
            ("x86", "64"),
            ("armsr", "armv7"),
            ("armsr", "armv8"),
            ("mediatek", "filogic"),
            ("rockchip", "armv8"),
            ("bcm27xx", "bcm2711"),
            ("qualcommax", "ipq807x"),
            ("ipq40xx", "generic"),
            ("mvebu", "cortexa53"),
            ("mvebu", "cortexa72"),
        ]
        for target, subtarget in common_targets:
            self.assertRegex(
                workflow,
                rf"target: {re.escape(target)}\n\s+subtarget: {re.escape(subtarget)}",
            )

    def test_docs_describe_independent_branch_and_common_arches(self) -> None:
        docs = (ROOT / "openwrt" / "README.md").read_text()

        self.assertIn("independent OpenWrt APK branch", docs)
        self.assertIn("codex/openwrt-25-apk", docs)
        self.assertIn("x86/64", docs)
        self.assertIn("armsr/armv7", docs)
        self.assertIn("mediatek/filogic", docs)
        self.assertIn("MIPS targets", docs)
        self.assertIn("build-std", docs)
        self.assertIn("openwrt/scripts/build-apk-docker.sh", docs)
        self.assertIn("OPENWRT_BUILD_JOBS", docs)

    def test_gitignore_keeps_local_codex_ecc_state_out_of_apk_changes(self) -> None:
        gitignore = (ROOT / ".gitignore").read_text()

        self.assertIn("/.agents", gitignore)
        self.assertIn("/.codex", gitignore)
        self.assertIn("/openwrt/.cache", gitignore)
        self.assertIn("/openwrt/dist", gitignore)


if __name__ == "__main__":
    unittest.main()

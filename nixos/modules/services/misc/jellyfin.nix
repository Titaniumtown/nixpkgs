{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib)
    mkIf
    mkDefault
    getExe
    maintainers
    mkEnableOption
    mkOption
    mkPackageOption
    boolToString
    escapeXML
    nameValuePair
    optionalString
    concatMapStringsSep
    escapeShellArg
    literalExpression
    ;
  inherit (lib.types)
    bool
    enum
    ints
    listOf
    nullOr
    path
    port
    str
    submodule
    ;
  cfg = config.services.jellyfin;
  filteredDecodingCodecs = builtins.filter (
    c: c != "hevcRExt10bit" && c != "hevcRExt12bit" && cfg.transcoding.hardwareDecodingCodecs.${c}
  ) (builtins.attrNames cfg.transcoding.hardwareDecodingCodecs);
  encodingXmlText = ''
    <?xml version="1.0" encoding="utf-8"?>
    <EncodingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <HardwareAccelerationType>${cfg.hardwareAcceleration.type}</HardwareAccelerationType>
      ${optionalString (
        cfg.hardwareAcceleration.type == "vaapi" && cfg.hardwareAcceleration.device != null
      ) "<VaapiDevice>${escapeXML cfg.hardwareAcceleration.device}</VaapiDevice>"}
      ${optionalString (
        cfg.hardwareAcceleration.type == "qsv" && cfg.hardwareAcceleration.device != null
      ) "<OpenclDevice>${escapeXML cfg.hardwareAcceleration.device}</OpenclDevice>"}
      <EncodingThreadCount>${
        if cfg.transcoding.threadCount != null then toString cfg.transcoding.threadCount else "-1"
      }</EncodingThreadCount>
      <EnableThrottling>${boolToString cfg.transcoding.throttleTranscoding}</EnableThrottling>
      <EnableTonemapping>${boolToString cfg.transcoding.enableToneMapping}</EnableTonemapping>
      <EnableSubtitleExtraction>${boolToString cfg.transcoding.enableSubtitleExtraction}</EnableSubtitleExtraction>
      <H264Crf>${toString cfg.transcoding.h264Crf}</H264Crf>
      <H265Crf>${toString cfg.transcoding.h265Crf}</H265Crf>
      <EnableHardwareEncoding>${boolToString cfg.transcoding.enableHardwareEncoding}</EnableHardwareEncoding>
      <AllowHevcEncoding>${boolToString cfg.transcoding.hardwareEncodingCodecs.hevc}</AllowHevcEncoding>
      <AllowAv1Encoding>${boolToString cfg.transcoding.hardwareEncodingCodecs.av1}</AllowAv1Encoding>
      <EnableIntelLowPowerH264HwEncoder>${boolToString cfg.transcoding.enableIntelLowPowerEncoding}</EnableIntelLowPowerH264HwEncoder>
      <EnableIntelLowPowerHevcHwEncoder>${boolToString cfg.transcoding.enableIntelLowPowerEncoding}</EnableIntelLowPowerHevcHwEncoder>
      <EnableDecodingColorDepth10HevcRext>${boolToString cfg.transcoding.hardwareDecodingCodecs.hevcRExt10bit}</EnableDecodingColorDepth10HevcRext>
      <EnableDecodingColorDepth12HevcRext>${boolToString cfg.transcoding.hardwareDecodingCodecs.hevcRExt12bit}</EnableDecodingColorDepth12HevcRext>
      <HardwareDecodingCodecs>
        ${concatMapStringsSep "\n    " (
          codec: "<string>${escapeXML codec}</string>"
        ) filteredDecodingCodecs}
      </HardwareDecodingCodecs>
    </EncodingOptions>
  '';
  encodingXmlFile = pkgs.writeText "encoding.xml" encodingXmlText;
  stringListToXml =
    tag: items:
    if items == [ ] then
      "<${tag} />"
    else
      "<${tag}>\n    ${
        concatMapStringsSep "\n    " (item: "<string>${escapeXML item}</string>") items
      }\n  </${tag}>";
  networkXmlText = ''
    <?xml version="1.0" encoding="utf-8"?>
    <NetworkConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <BaseUrl>${escapeXML cfg.network.baseUrl}</BaseUrl>
      <EnableHttps>${boolToString cfg.network.enableHttps}</EnableHttps>
      <RequireHttps>${boolToString cfg.network.requireHttps}</RequireHttps>
      <InternalHttpPort>${toString cfg.network.internalHttpPort}</InternalHttpPort>
      <InternalHttpsPort>${toString cfg.network.internalHttpsPort}</InternalHttpsPort>
      <PublicHttpPort>${toString cfg.network.publicHttpPort}</PublicHttpPort>
      <PublicHttpsPort>${toString cfg.network.publicHttpsPort}</PublicHttpsPort>
      <AutoDiscovery>${boolToString cfg.network.autoDiscovery}</AutoDiscovery>
      <EnableUPnP>${boolToString cfg.network.enableUPnP}</EnableUPnP>
      <EnableIPv4>${boolToString cfg.network.enableIPv4}</EnableIPv4>
      <EnableIPv6>${boolToString cfg.network.enableIPv6}</EnableIPv6>
      <EnableRemoteAccess>${boolToString cfg.network.enableRemoteAccess}</EnableRemoteAccess>
      ${stringListToXml "LocalNetworkSubnets" cfg.network.localNetworkSubnets}
      ${stringListToXml "LocalNetworkAddresses" cfg.network.localNetworkAddresses}
      ${stringListToXml "KnownProxies" cfg.network.knownProxies}
      <IgnoreVirtualInterfaces>${boolToString cfg.network.ignoreVirtualInterfaces}</IgnoreVirtualInterfaces>
      ${stringListToXml "VirtualInterfaceNames" cfg.network.virtualInterfaceNames}
      <EnablePublishedServerUriByRequest>${boolToString cfg.network.enablePublishedServerUriByRequest}</EnablePublishedServerUriByRequest>
      ${stringListToXml "PublishedServerUriBySubnet" cfg.network.publishedServerUriBySubnet}
      ${stringListToXml "RemoteIPFilter" cfg.network.remoteIPFilter}
      <IsRemoteIPFilterBlacklist>${boolToString cfg.network.isRemoteIPFilterBlacklist}</IsRemoteIPFilterBlacklist>
    </NetworkConfiguration>
  '';
  networkXmlFile = pkgs.writeText "network.xml" networkXmlText;
  codecListToType =
    desc: list:
    submodule {
      options = builtins.listToAttrs (
        map (
          name:
          nameValuePair name (mkOption {
            type = bool;
            default = false;
            description = "Enable ${desc} for ${name} codec.";
          })
        ) list
      );
    };
in
{
  options = {
    services.jellyfin = {
      enable = mkEnableOption "Jellyfin Media Server";

      package = mkPackageOption pkgs "jellyfin" { };

      user = mkOption {
        type = str;
        default = "jellyfin";
        description = "User account under which Jellyfin runs.";
      };

      group = mkOption {
        type = str;
        default = "jellyfin";
        description = "Group under which jellyfin runs.";
      };

      dataDir = mkOption {
        type = path;
        default = "/var/lib/jellyfin";
        description = ''
          Base data directory,
          passed with `--datadir` see [#data-directory](https://jellyfin.org/docs/general/administration/configuration/#data-directory)
        '';
      };

      configDir = mkOption {
        type = path;
        default = "${cfg.dataDir}/config";
        defaultText = literalExpression ''"''${cfg.dataDir}/config"'';
        description = ''
          Directory containing the server configuration files,
          passed with `--configdir` see [configuration-directory](https://jellyfin.org/docs/general/administration/configuration/#configuration-directory)
        '';
      };

      cacheDir = mkOption {
        type = path;
        default = "/var/cache/jellyfin";
        description = ''
          Directory containing the jellyfin server cache,
          passed with `--cachedir` see [#cache-directory](https://jellyfin.org/docs/general/administration/configuration/#cache-directory)
        '';
      };

      logDir = mkOption {
        type = path;
        default = "${cfg.dataDir}/log";
        defaultText = literalExpression ''"''${cfg.dataDir}/log"'';
        description = ''
          Directory where the Jellyfin logs will be stored,
          passed with `--logdir` see [#log-directory](https://jellyfin.org/docs/general/administration/configuration/#log-directory)
        '';
      };

      openFirewall = mkOption {
        type = bool;
        default = false;
        description = ''
          Open the default ports in the firewall for the media server. The
          HTTP/HTTPS ports can be changed in the Web UI, so this option should
          only be used if they are unchanged, see [Port Bindings](https://jellyfin.org/docs/general/networking/#port-bindings).
        '';
      };

      hardwareAcceleration = {
        enable = mkEnableOption "hardware acceleration for video transcoding";

        device = mkOption {
          type = nullOr path;
          default = null;
          example = "/dev/dri/renderD128";
          description = ''
            Path to the hardware acceleration device that Jellyfin should use.
            For obscure configurations, additional devices can be added via
            {option}`systemd.services.jellyfin.serviceConfig.DeviceAllow`.
          '';
        };

        # see MediaBrowser.Model/Entities/HardwareAccelerationType.cs in jellyfin source
        type = mkOption {
          type = enum [
            "none"
            "amf"
            "qsv"
            "nvenc"
            "v4l2m2m"
            "vaapi"
            # videotoolbox is MacOS-only
            "rkmpp"
          ];
          default = "none";
          description = ''
            The method of hardware acceleration. See [Hardware Acceleration](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration) for more details.
          '';
        };
      };

      forceEncodingConfig = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether to overwrite Jellyfin's `encoding.xml` configuration file on each service start.

          When enabled, the encoding configuration specified in {option}`services.jellyfin.transcoding`
          and {option}`services.jellyfin.hardwareAcceleration` will be applied on every service restart.
          A backup of the existing `encoding.xml` will be created at `encoding.xml.backup-$timestamp`.

          ::: {.warning}
          Enabling this option means that any changes made to transcoding settings through
          Jellyfin's web dashboard will be lost on the next service restart. The NixOS configuration
          becomes the single source of truth for encoding settings.
          :::

          When disabled (the default), the encoding configuration is only written if no `encoding.xml`
          exists yet. This allows settings to be changed through Jellyfin's web dashboard and persist
          across restarts, but means the NixOS configuration options will be ignored after the initial setup.
        '';
      };

      network = {
        baseUrl = mkOption {
          type = str;
          default = "";
          example = "/jellyfin";
          description = ''
            Prefix added to Jellyfin's internal URLs when it sits behind a reverse proxy at a sub-path.
            Leave empty when Jellyfin is served at the root of its host.
          '';
        };

        enableHttps = mkOption {
          type = bool;
          default = false;
          description = ''
            Serve HTTPS directly from Jellyfin. Usually unnecessary when terminating TLS in a reverse proxy.
          '';
        };

        requireHttps = mkOption {
          type = bool;
          default = false;
          description = ''
            Redirect plaintext HTTP requests to HTTPS. Only meaningful when {option}`enableHttps` is true.
          '';
        };

        internalHttpPort = mkOption {
          type = port;
          default = 8096;
          description = "TCP port Jellyfin binds for HTTP.";
        };

        internalHttpsPort = mkOption {
          type = port;
          default = 8920;
          description = "TCP port Jellyfin binds for HTTPS. Only used when {option}`enableHttps` is true.";
        };

        publicHttpPort = mkOption {
          type = port;
          default = 8096;
          description = "HTTP port Jellyfin advertises in server discovery responses and published URIs.";
        };

        publicHttpsPort = mkOption {
          type = port;
          default = 8920;
          description = "HTTPS port Jellyfin advertises in server discovery responses and published URIs.";
        };

        autoDiscovery = mkOption {
          type = bool;
          default = true;
          description = "Respond to LAN client auto-discovery broadcasts (UDP 7359).";
        };

        enableUPnP = mkOption {
          type = bool;
          default = false;
          description = "Attempt to open the public ports on the router via UPnP.";
        };

        enableIPv4 = mkOption {
          type = bool;
          default = true;
          description = "Listen on IPv4.";
        };

        enableIPv6 = mkOption {
          type = bool;
          default = true;
          description = "Listen on IPv6.";
        };

        enableRemoteAccess = mkOption {
          type = bool;
          default = true;
          description = ''
            Allow connections from clients outside the subnets listed in {option}`localNetworkSubnets`.
            When false, Jellyfin rejects non-local requests regardless of reverse proxy configuration.
          '';
        };

        localNetworkSubnets = mkOption {
          type = listOf str;
          default = [ ];
          example = [
            "192.168.1.0/24"
            "10.0.0.0/8"
          ];
          description = ''
            CIDR ranges (or bare IPs) that Jellyfin classifies as the local network.
            Clients originating from these ranges -- as seen after {option}`knownProxies` X-Forwarded-For
            unwrapping -- are not subject to {option}`services.jellyfin` remote-client bitrate limits.
          '';
        };

        localNetworkAddresses = mkOption {
          type = listOf str;
          default = [ ];
          example = [ "192.168.1.50" ];
          description = ''
            Specific interface addresses Jellyfin binds to. Leave empty to bind all interfaces.
          '';
        };

        knownProxies = mkOption {
          type = listOf str;
          default = [ ];
          example = [ "127.0.0.1" ];
          description = ''
            Addresses of reverse proxies trusted to forward the real client IP via `X-Forwarded-For`.
            Without this, Jellyfin sees the proxy's address for every request and cannot apply
            {option}`localNetworkSubnets` classification to the true client.
          '';
        };

        ignoreVirtualInterfaces = mkOption {
          type = bool;
          default = true;
          description = "Skip virtual network interfaces (matching {option}`virtualInterfaceNames`) during auto-bind.";
        };

        virtualInterfaceNames = mkOption {
          type = listOf str;
          default = [ "veth" ];
          description = "Interface name prefixes treated as virtual when {option}`ignoreVirtualInterfaces` is true.";
        };

        enablePublishedServerUriByRequest = mkOption {
          type = bool;
          default = false;
          description = ''
            Derive the server's public URI from the incoming request's Host header instead of any
            configured {option}`publishedServerUriBySubnet` entry.
          '';
        };

        publishedServerUriBySubnet = mkOption {
          type = listOf str;
          default = [ ];
          example = [ "192.168.1.0/24=http://jellyfin.lan:8096" ];
          description = ''
            Per-subnet overrides for the URI Jellyfin advertises to clients, in `subnet=uri` form.
          '';
        };

        remoteIPFilter = mkOption {
          type = listOf str;
          default = [ ];
          example = [ "203.0.113.0/24" ];
          description = ''
            IPs or CIDRs used as the allow- or denylist for remote access.
            Behaviour is controlled by {option}`isRemoteIPFilterBlacklist`.
          '';
        };

        isRemoteIPFilterBlacklist = mkOption {
          type = bool;
          default = false;
          description = ''
            When true, {option}`remoteIPFilter` is a denylist; when false, it is an allowlist
            (and an empty list allows all remote addresses).
          '';
        };
      };

      forceNetworkConfig = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether to overwrite Jellyfin's `network.xml` configuration file on each service start.

          When enabled, the network configuration specified in {option}`services.jellyfin.network`
          is applied on every service restart. A backup of the existing `network.xml` will be
          created at `network.xml.backup-$timestamp`.

          ::: {.warning}
          Enabling this option means that any changes made to networking settings through
          Jellyfin's web dashboard will be lost on the next service restart. The NixOS configuration
          becomes the single source of truth for network settings.
          :::

          When disabled (the default), the network configuration is only written if no `network.xml`
          exists yet. This allows settings to be changed through Jellyfin's web dashboard and persist
          across restarts, but means the NixOS configuration options will be ignored after the initial setup.
        '';
      };

      transcoding = {
        maxConcurrentStreams = mkOption {
          type = nullOr ints.positive;
          default = null;
          example = 2;
          description = ''
            Maximum number of concurrent transcoding streams.
            Set to null for unlimited (limited by hardware capabilities).
          '';
        };

        enableToneMapping = mkOption {
          type = bool;
          default = true;
          description = ''
            Enable tone mapping when transcoding HDR content.
          '';
        };

        enableSubtitleExtraction = mkOption {
          type = bool;
          default = true;
          description = ''
            Embedded subtitles can be extracted from videos and delivered to clients in plain text, in order to help prevent video transcoding. On some systems this can take a long time and cause video playback to stall during the extraction process. Disable this to have embedded subtitles burned in with video transcoding when they are not natively supported by the client device.
          '';
        };

        throttleTranscoding = mkOption {
          type = bool;
          default = false;
          description = ''
            When a transcode or remux gets far enough ahead from the current playback position, pause the process so it will consume fewer resources. This is most useful when watching without seeking often. Turn this off if you experience playback issues.
          '';
        };

        threadCount = mkOption {
          type = nullOr ints.positive;
          default = null;
          example = 4;
          description = ''
            Number of threads to use when transcoding.
            Set to null to use automatic detection.
          '';
        };

        hardwareDecodingCodecs = mkOption {
          type = codecListToType "hardware decoding" [
            "h264"
            "hevc"
            "mpeg2"
            "vc1"
            "vp8"
            "vp9"
            "av1"
            "hevc10bit"
            "hevcRExt10bit"
            "hevcRExt12bit"
          ];
          default = { };
          example = {
            vp9 = true;
            h264 = true;
          };
          description = ''
            Which codecs to enable for hardware decoding.
          '';
        };

        hardwareEncodingCodecs = mkOption {
          type = codecListToType "hardware encoding" [
            "hevc"
            "av1"
          ];
          default = { };
          example = {
            av1 = true;
          };
          description = ''
            Which codecs to enable for hardware encoding. h264 is always enabled.
          '';
        };

        encodingPreset = mkOption {
          type = enum [
            "auto"
            "veryslow"
            "slower"
            "slow"
            "medium"
            "fast"
            "faster"
            "veryfast"
            "superfast"
            "ultrafast"
          ];
          default = "auto";
          description = ''
            Encoder preset for transcoding.
            Lower presets sacrifice quality for speed, higher presets optimize quality.
          '';
        };

        deleteSegments = mkOption {
          type = bool;
          default = true;
          description = ''
            Delete transcoding segments when finished.
          '';
        };

        h264Crf = mkOption {
          type = ints.between 0 51;
          default = 23;
          description = ''
            Constant Rate Factor (CRF) for H.264 encoding. Lower values result in better quality. Range: 0-51.
          '';
        };

        h265Crf = mkOption {
          type = ints.between 0 51;
          default = 28;
          description = ''
            Constant Rate Factor (CRF) for H.265 encoding. Lower values result in better quality. Range: 0-51.
          '';
        };

        enableHardwareEncoding = mkOption {
          type = bool;
          default = false;
          description = ''
            Enable hardware encoding for video transcoding.
          '';
        };

        enableIntelLowPowerEncoding = mkOption {
          type = bool;
          default = false;
          description = ''
            Enable low-power encoding mode for Intel Quick Sync Video.
            Requires i915 HuC firmware to be configured.
          '';
        };
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hardwareAcceleration.enable -> cfg.hardwareAcceleration.device != null;
        message = "services.jellyfin.hardwareAcceleration.device cannot be null when hardware acceleration is enabled.";
      }
    ];

    systemd = {
      tmpfiles.settings.jellyfinDirs = {
        "${cfg.dataDir}"."d" = {
          mode = "700";
          inherit (cfg) user group;
        };
        "${cfg.configDir}"."d" = {
          mode = "700";
          inherit (cfg) user group;
        };
        "${cfg.logDir}"."d" = {
          mode = "700";
          inherit (cfg) user group;
        };
        "${cfg.cacheDir}"."d" = {
          mode = "700";
          inherit (cfg) user group;
        };
      };
      services.jellyfin = {
        description = "Jellyfin Media Server";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        preStart =
          let
            # manage_config_xml <source> <destination> <force> <description>
            #
            # Installs a NixOS-declared XML config at <destination>, preserving
            # any existing file as a timestamped backup when <force> is true.
            # With <force>=false, leaves existing files untouched and warns if
            # the on-disk content differs from the declared content.
            helper = ''
              manage_config_xml() {
                local src="$1" dest="$2" force="$3" desc="$4"
                if [[ -e "$dest" ]]; then
                  # this intentionally removes trailing newlines
                  local currentText configuredText
                  currentText="$(<"$dest")"
                  configuredText="$(<"$src")"
                  if [[ "$currentText" == "$configuredText" ]]; then
                    return 0
                  fi
                  if [[ "$force" == true ]]; then
                    local backup
                    backup="$dest.backup-$(date -u +"%FT%H_%M_%SZ")"
                    mv --update=none-fail -T "$dest" "$backup"
                  else
                    echo "WARN: $dest already exists and is different from the configured settings. $desc options NOT applied." >&2
                    echo "WARN: Set the corresponding force*Config option to override." >&2
                    return 0
                  fi
                fi
                cp --update=none-fail -T "$src" "$dest"
                chmod u+w "$dest"
              }
              configDir=${escapeShellArg cfg.configDir}
            '';
          in
          (
            helper
            + optionalString cfg.hardwareAcceleration.enable ''
              manage_config_xml ${encodingXmlFile} "$configDir/encoding.xml" ${boolToString cfg.forceEncodingConfig} transcoding
            ''
            + ''
              manage_config_xml ${networkXmlFile} "$configDir/network.xml" ${boolToString cfg.forceNetworkConfig} network
            ''
          );

        # This is mostly follows: https://github.com/jellyfin/jellyfin/blob/master/fedora/jellyfin.service
        # Upstream also disable some hardenings when running in LXC, we do the same with the isContainer option
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          UMask = "0077";
          WorkingDirectory = cfg.dataDir;
          ExecStart = "${getExe cfg.package} --datadir '${cfg.dataDir}' --configdir '${cfg.configDir}' --cachedir '${cfg.cacheDir}' --logdir '${cfg.logDir}'";
          Restart = "on-failure";
          TimeoutSec = 15;
          SuccessExitStatus = [
            "0"
            "143"
          ];

          # Security options:
          CapabilityBoundingSet = [ "" ];
          NoNewPrivileges = true;
          SystemCallArchitectures = "native";
          # AF_NETLINK needed because Jellyfin monitors the network connection
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
          ];
          RestrictNamespaces = !config.boot.isContainer;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          ProcSubset = "pid";
          ProtectControlGroups = !config.boot.isContainer;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = !config.boot.isContainer;
          ProtectKernelModules = !config.boot.isContainer;
          ProtectKernelTunables = !config.boot.isContainer;
          ProtectProc = "invisible";
          ProtectSystem = true;
          LockPersonality = true;
          PrivateTmp = !config.boot.isContainer;
          # needed for hardware acceleration
          # PrivateDevices defaults to false for backwards compatibility - users may have
          # hardware acceleration set up outside of NixOS configuration
          PrivateDevices = mkDefault false;
          DeviceAllow = mkIf cfg.hardwareAcceleration.enable [ "${cfg.hardwareAcceleration.device} rw" ];
          PrivateUsers = true;
          RemoveIPC = true;

          SystemCallFilter = [
            "@system-service"
            "~@privileged"
          ];
          SystemCallErrorNumber = "EPERM";
        };
      };
    };

    users.users = mkIf (cfg.user == "jellyfin") {
      jellyfin = {
        inherit (cfg) group;
        isSystemUser = true;
      };
    };

    users.groups = mkIf (cfg.group == "jellyfin") {
      jellyfin = { };
    };

    networking.firewall = mkIf cfg.openFirewall {
      # from https://jellyfin.org/docs/general/networking/index.html
      allowedTCPPorts = [
        8096
        8920
      ];
      allowedUDPPorts = [
        1900
        7359
      ];
    };

  };

  meta.maintainers = with maintainers; [
    minijackson
    fsnkty
  ];
}

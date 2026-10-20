{ pkgs }:
let
  package = builtins.fromJSON (builtins.readFile ./package.json);
  version = package.dependencies."@deepseek-ai/dsh";
  nodejs = import ./nodejs.nix { inherit pkgs; };
  pnpm = pkgs.pnpm_11.override { nodejs-slim = nodejs; };
  modules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = ./.;
    inherit nodejs;
    derivationArgs = {
      npmFlags = [ "--ignore-scripts" ];
    };
  };
  dsh = pkgs.runCommand "dsh-${version}" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p "$out/bin" "$out/lib"
    ln -s ${modules}/node_modules "$out/lib/node_modules"
    makeWrapper ${nodejs}/bin/node "$out/bin/dsh" \
      --add-flags "$out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js"
  '';
  entrypoint = pkgs.writeScriptBin "wishmachine-entrypoint" (builtins.readFile ../runtime/entrypoint.sh);
  environment = pkgs.buildEnv {
    name = "wishmachine-environment";
    paths = [
      nodejs pnpm dsh entrypoint
      pkgs.bashInteractive pkgs.coreutils pkgs.findutils pkgs.gnugrep
      pkgs.gnused pkgs.gnutar pkgs.gzip pkgs.unzip pkgs.diffutils
      pkgs.git pkgs.jujutsu pkgs.gh pkgs.openssh pkgs.ripgrep pkgs.curl
      pkgs.cacert pkgs.cloudflared pkgs.tini pkgs.procps
    ];
    pathsToLink = [ "/bin" "/etc" "/share" ];
  };
  runtimeEnv = [
    "PATH=/home/agent/.local/bin:/bin"
    "HOME=/home/agent"
    "DSH_HOME=/home/agent/.dsh"
    "XDG_CACHE_HOME=/home/agent/.cache"
    "XDG_CONFIG_HOME=/home/agent/.config"
    "XDG_DATA_HOME=/home/agent/.local/share"
    "SHELL=/bin/bash"
    "LANG=C.UTF-8"
    "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    "NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-bundle.crt"
  ];
  sshConfig = pkgs.writeText "wishmachine-sshd-config" ''
    ListenAddress 127.0.0.1
    Port 2222
    AllowUsers agent
    PermitRootLogin no
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PubkeyAuthentication yes
    UsePAM no
    PidFile none
    Subsystem sftp internal-sftp
    SetEnv ${builtins.concatStringsSep " " runtimeEnv}
  '';
  image = pkgs.dockerTools.buildLayeredImage {
    name = "ghcr.io/ovler-young/wishmachine";
    tag = "dsh-${version}";
    contents = [ environment ];
    extraCommands = ''
      mkdir -p home/agent workspace tmp usr/bin etc
      ln -s ${sshConfig} etc/wishmachine-sshd_config
      chmod 1777 tmp
      ln -s ${pkgs.coreutils}/bin/env usr/bin/env
      cat > etc/passwd <<'PASSWD'
      root:x:0:0:root:/root:/bin/bash
      agent:x:1000:1000:Agent:/home/agent:/bin/bash
      PASSWD
      cat > etc/group <<'GROUP'
      root:x:0:
      agent:x:1000:
      GROUP
      echo 'hosts: files dns' > etc/nsswitch.conf
    '';
    fakeRootCommands = ''
      chown 1000:1000 home/agent workspace
    '';
    config = {
      User = "1000:1000";
      WorkingDir = "/workspace";
      Entrypoint = [ "${pkgs.tini}/bin/tini" "-g" "--" "/bin/wishmachine-entrypoint" ];
      Env = runtimeEnv;
      Labels = {
        "org.opencontainers.image.title" = "Wishmachine";
        "org.opencontainers.image.source" = "https://github.com/Ovler-Young/wishmachine";
        "org.opencontainers.image.version" = version;
      };
    };
  };
in {
  inherit dsh image;
}

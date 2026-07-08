{ config, pkgs, lib, ... }:
let
  cfg = config.services.hello-world;

  # Static HTML built into the Nix store — no backend process needed.
  htmlDir = pkgs.writeTextDir "index.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>Hello from ${config.networking.hostName}</title>
      <style>
        body { font-family: sans-serif; max-width: 600px; margin: 4rem auto; padding: 0 1rem; }
        h1   { color: #333; }
        p    { color: #555; }
      </style>
    </head>
    <body>
      <h1>Hello from ${config.networking.hostName}</h1>
      <p>Caddy reverse proxy and wildcard TLS are working correctly.</p>
    </body>
    </html>
  '';
in {
  options.services.hello-world = {
    enable = lib.mkEnableOption "Hello World static test page (Caddy smoke test)";
  };

  # Adds hello.<domain> to Caddy — only meaningful when caddy-server is also enabled.
  config = lib.mkIf cfg.enable {
    services.caddy.virtualHosts = lib.mkIf config.services.caddy-server.enable {
      "hello.${config.services.caddy-server.domain}" = {
        useACMEHost = config.services.caddy-server.domain;
        extraConfig = ''
          root * ${htmlDir}
          file_server
        '';
      };
    };
  };
}

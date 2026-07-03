# NixOS machine configurations.
#
# Add a homelab machine by creating:
#   modules/machines/nixos/<hostname>/configuration.nix
#
# Then register it in flake.nix outputs.nixosConfigurations:
#
#   inputs.nixpkgs.lib.nixosSystem {
#     system = "x86_64-linux";
#     specialArgs = { inherit inputs; };
#     modules = [
#       ./modules/machines/nixos/_common
#       ./modules/machines/nixos/<hostname>/configuration.nix
#       inputs.home-manager.nixosModules.home-manager
#       {
#         home-manager.useGlobalPkgs    = true;
#         home-manager.useUserPackages  = true;
#         home-manager.extraSpecialArgs = { inherit inputs; };
#         home-manager.users.galac      = import ./modules/home/galac;
#       }
#     ];
#   }
#
# home/galac/default.nix detects the platform automatically and sets
# homeDirectory to /home/galac on Linux. The dots/* modules are
# platform-agnostic and work unchanged on NixOS.

{ }

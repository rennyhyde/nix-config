# NixOS machine configurations.
#
# Add a homelab machine by creating:
#   modules/nixos/<hostname>/configuration.nix
#
# Then register it here following the pattern below and add it to
# flake.nix outputs.nixosConfigurations.
#
# Example (uncomment and adapt when ready):
#
#   inputs.nixpkgs.lib.nixosSystem {
#     system = "x86_64-linux";
#     specialArgs = { inherit inputs; };
#     modules = [
#       ./_common
#       ./<hostname>/configuration.nix
#       inputs.home-manager.nixosModules.home-manager
#       {
#         home-manager.useGlobalPkgs    = true;
#         home-manager.useUserPackages  = true;
#         home-manager.extraSpecialArgs = { inherit inputs; };
#         home-manager.users.galac      = import ../home/galac;
#       }
#     ];
#   }
#
# home/galac/default.nix detects the platform automatically and sets
# homeDirectory to /home/galac on Linux. The dots/* modules are
# platform-agnostic and work unchanged on NixOS.

{ }

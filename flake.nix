{
  description = "pocket nix!";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Nix Darwin
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    darwin-login-items.url = "github:uncenter/nix-darwin-login-items";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, darwin-login-items}:
  {
    darwinConfigurations."rny-macbook" = import ./modules/darwin {
      inherit inputs nixpkgs nix-darwin darwin-login-items home-manager;
    };

    nixosConfigurations."lovefield" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./modules/nixos/_common
        ./modules/nixos/lovefield/configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs    = true;
          home-manager.useUserPackages  = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.galac      = import ./modules/home/galac;
        }
      ];
    };
  };
}
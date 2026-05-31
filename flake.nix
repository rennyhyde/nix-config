{
  description = "Renny's macOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    darwin-login-items.url = "github:uncenter/nix-darwin-login-items";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, darwin-login-items}:
  {
    darwinConfigurations."rny-macbook" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";  # Apple Silicon; use x86_64-darwin for Intel
      modules = [
        ./configuration.nix
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.galac = import ./home.nix;
        }
	  darwin-login-items.darwinModules.default
      ];
    };
  };
}

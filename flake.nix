{
  description = "pocket nix!";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    darwin-login-items.url = "github:uncenter/nix-darwin-login-items";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, darwin-login-items}:
  {
    darwinConfigurations."rny-macbook" = import ./modules/darwin {
      inherit inputs nixpkgs nix-darwin darwin-login-items home-manager;
    };
  };
}
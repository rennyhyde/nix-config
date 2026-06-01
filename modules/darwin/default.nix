{ inputs, nixpkgs, nix-darwin, darwin-login-items, home-manager }:

nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";

  # specialArgs makes these available as function arguments in every nix-darwin module
  specialArgs = { inherit inputs; };

  modules = [
    ./_common

    ./rny-macbook/configuration.nix
    ./rny-macbook/system.nix

    darwin-login-items.darwinModules.default

    home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      # extraSpecialArgs makes `inputs` available inside home-manager modules too
      home-manager.extraSpecialArgs = { inherit inputs; };
      home-manager.users.galac = import ../home/galac;
    }
  ];
}

# Builds a MicroVM from a flake but takes the hypervisor from the
# local pkgs not from the target flake.
{ self
, lib, targetPlatform
, writeScriptBin, runtimeShell
, coreutils, git, nix
}:

writeScriptBin "build-microvm" ''
  #! ${runtimeShell} -e

  IFS=`echo`
  PATH=${lib.makeBinPath [ coreutils git nix ]}

  if [ $# -lt 1 ]; then
    echo Usage: $0 flakeref#nixos
    exit 1
  fi

  FLAKE=$(echo $1|cut -d "#" -f 1)
  NAME=$(echo $1|cut -d "#" -f 2)
  shift
  ARGS=("$@")

  echo Building a MicroVM runner for NixOS configuration $NAME from Flake $FLAKE
  # --impure so that we can getFlake /nix/store/...
  nix build "''${ARGS[@]}" --impure --expr "let
    self = builtins.getFlake \"${self}\";
    pkgs = self.inputs.nixpkgs.legacyPackages.${targetPlatform.system};
    flake = builtins.getFlake \"$FLAKE\";
    original = flake.nixosConfigurations.\"$NAME\";
    extended =
      if original.config ? microvm
      # Already a MicroVM
      then original
      # Otherwise turn into one
      else original.extendModules {
        modules = [
          self.nixosModules.microvm
        ];
      };
    inherit (extended.config.boot.kernelPackages) kernel;
    rootDisk = self.lib.buildSquashfs {
      inherit pkgs;
      inherit (extended) config;
    };
  in self.lib.buildRunner {
    inherit pkgs kernel rootDisk;
    microvmConfig = {
      inherit (extended.config.networking) hostName;
    } // extended.config.microvm;
    inherit (extended.config.system.build) toplevel;
  }"
''

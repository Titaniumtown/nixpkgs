{ stdenvNoCC, lib, fetchgit }:
stdenvNoCC.mkDerivation rec {
  pname = "ti-firmware";
  version = "10.00.04";

  src = fetchgit {
    url = "https://git.ti.com/git/processor-firmware/ti-linux-firmware.git";
    rev = "9c4fb99cbdafd638dba16aaced4488953bc5937b";
    sha256 = "pBF9QMpQ+Zz6dG9+XQoBKm0fb8vh3+BB+QHm2BZXdic=";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/firmware
    cp -a * $out/lib/firmware/

    runHook postInstall
  '';

  # Firmware blobs do not need fixing and should not be modified
  dontBuild = true;
  dontFixup = true;

  meta = with lib; {
    description = "Firmware from Texas Instruments";
    homepage = "https://git.ti.com/cgit/processor-firmware/ti-linux-firmware";
    license = licenses.unfree;
    platforms = platforms.all;
    maintainers = with maintainers; [ titaniumtown ];
  };
}

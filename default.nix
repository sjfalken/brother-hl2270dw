{
  lib,
  stdenv,
  fetchurl,
  cpio,
  makeWrapper,
  patchelf,
  coreutils,
  gnugrep,
  gnused,
  gawk,
  ghostscript,
  a2ps,
  file,
  perl,
  which,
  pkgsi686Linux,
}:

let
  model = "HL2270DW";
  version = "2.1.0";
in
stdenv.mkDerivation rec {
  pname = "brother-hl2270dw";
  inherit version;

  srcs = [
    (fetchurl {
      url = "http://www.brother.com/pub/bsc/linux/dlf/hl2270dwlpr-2.1.0-1.i386.rpm";
      hash = "sha256-hlhkEbo4hstrxXcMmO2PlOQF5a+UG6EKm0i5Z5gv+co=";
    })
    (fetchurl {
      url = "http://www.brother.com/pub/bsc/linux/dlf/cupswrapperHL2270DW-2.0.4-2.i386.rpm";
      hash = "sha256-htMNp0xBqde2GVx63cOC7AjnW1MrQduu6YOvIDzmZOw=";
    })
  ];

  nativeBuildInputs = [ makeWrapper cpio patchelf ];

  buildInputs = [
    coreutils
    gnugrep
    gnused
    gawk
    ghostscript
    a2ps
    file
    perl
    which
  ];

  unpackPhase = ''
    for src in $srcs; do
      ${pkgsi686Linux.rpm}/bin/rpm2cpio "$src" | cpio -idmv
    done
  '';

  patchPhase = ''
    CUPSWRAPPER="usr/local/Brother/Printer/${model}/cupswrapper/cupswrapperHL2270DW-2.0.4"
    LPDFILTER="usr/local/Brother/Printer/${model}/lpd/filterHL2270DW"
    PSCONVERT="usr/local/Brother/Printer/${model}/lpd/psconvert2"

    # Truncate the cupswrapper script after the PPD extraction (before the filter part)
    sed -i -e '/^!ENDOFWFILTER!/ q' "$CUPSWRAPPER"

    # Point the cupswrapper script at our build directory for PPD extraction
    sed -i -e "s|/usr|$PWD/usr|" "$CUPSWRAPPER"

    # Fix /usr/local -> /usr/share in the LPD filter
    substituteInPlace "$LPDFILTER" --replace-warn "/usr/local" "/usr/share"

    # Create the model directory so the PPD extraction works
    mkdir -p usr/share/cups/model/

    # Run the cupswrapper script to extract the PPD file
    bash "$CUPSWRAPPER"

    # Restore paths in extracted PPD wrapper filter
    # Replace $PWD/usr/local with $out/share first (more specific), then $PWD/usr with $out
    if [ -f usr/lib/cups/filter/brlpdwrapperHL2270DW ]; then
      substituteInPlace usr/lib/cups/filter/brlpdwrapperHL2270DW \
        --replace-warn "$PWD/usr/local" "$out/share" \
        --replace-warn "$PWD/usr" "$out"
      chmod +x usr/lib/cups/filter/brlpdwrapperHL2270DW
    fi

    # Fix the PPD description
    sed -i -e 's/Brother HL2270DW for CUPS/Brother HL-2270DW/' \
      usr/share/cups/model/HL2270DW.ppd

    # Apply margin correction patch
    patch usr/share/cups/model/HL2270DW.ppd < ${./HL2270DW.ppd.patch}

    # Fix pstops paths
    substituteInPlace "$PSCONVERT" \
      --replace-warn "/usr/sbin/pstops" "pstops"
    substituteInPlace "$LPDFILTER" \
      --replace-warn "/usr/bin/pstops" "pstops"

    # Patch hardcoded /usr/local/ in binaries (same length as /usr/share/)
    for bin in \
      "usr/local/Brother/Printer/${model}/cupswrapper/brcupsconfig4" \
      "usr/local/Brother/Printer/${model}/inf/brprintconflsr3" \
      "usr/local/Brother/Printer/${model}/inf/braddprinter"; do
      if [ -f "$bin" ]; then
        sed -i -e 's|/usr/local/|/usr/share/|g' "$bin"
      fi
    done
  '';

  installPhase = ''
    # Set up standard CUPS directories
    mkdir -p $out/lib/cups/filter
    mkdir -p $out/share/cups/model
    mkdir -p $out/share/Brother/Printer/${model}

    # Install PPD
    cp usr/share/cups/model/HL2270DW.ppd $out/share/cups/model/

    # Install Brother driver files
    cp -R usr/local/Brother/Printer/${model}/* $out/share/Brother/Printer/${model}/

    # Remove the cupswrapper install script (no longer needed)
    rm -f $out/share/Brother/Printer/${model}/cupswrapper/cupswrapperHL2270DW-2.0.4
    # Remove setupPrintcap2 (not needed on NixOS)
    rm -f $out/share/Brother/Printer/${model}/inf/setupPrintcap2

    # Install CUPS filter wrapper
    if [ -f usr/lib/cups/filter/brlpdwrapperHL2270DW ]; then
      cp usr/lib/cups/filter/brlpdwrapperHL2270DW $out/lib/cups/filter/
    fi

    # Fix paths in LPD scripts to point to $out
    for f in $out/share/Brother/Printer/${model}/lpd/filterHL2270DW \
             $out/share/Brother/Printer/${model}/lpd/psconvert2; do
      if [ -f "$f" ]; then
        substituteInPlace "$f" --replace-quiet "/usr/share/Brother" "$out/share/Brother"
      fi
    done

    # Fix path references in the PPD to point to the Nix store
    substituteInPlace $out/share/cups/model/HL2270DW.ppd \
      --replace-quiet "/usr/lib/cups/filter" "$out/lib/cups/filter"

    # Patch ELF binaries with correct interpreter for i386
    for bin in \
      $out/share/Brother/Printer/${model}/cupswrapper/brcupsconfig4 \
      $out/share/Brother/Printer/${model}/inf/brprintconflsr3 \
      $out/share/Brother/Printer/${model}/inf/braddprinter \
      $out/share/Brother/Printer/${model}/lpd/rawtobr3 \
      $out/share/Brother/Printer/${model}/lpd/brprintconflsr3; do
      if [ -f "$bin" ] && file "$bin" | grep -q "ELF"; then
        patchelf --set-interpreter ${pkgsi686Linux.glibc}/lib/ld-linux.so.2 "$bin" || true
      fi
    done

    # Make config file writable at runtime via /var
    chmod a+w $out/share/Brother/Printer/${model}/inf/brHL2270DWrc || true

    # Wrap scripts with required PATH
    for f in $out/lib/cups/filter/brlpdwrapperHL2270DW; do
      if [ -f "$f" ]; then
        wrapProgram "$f" \
          --prefix PATH : ${lib.makeBinPath [
            coreutils gnugrep gnused gawk ghostscript a2ps file perl which
          ]}
      fi
    done

    for f in $out/share/Brother/Printer/${model}/lpd/filterHL2270DW \
             $out/share/Brother/Printer/${model}/lpd/psconvert2; do
      if [ -f "$f" ]; then
        wrapProgram "$f" \
          --prefix PATH : ${lib.makeBinPath [
            coreutils gnugrep gnused gawk ghostscript a2ps file perl which
          ]}
      fi
    done
  '';

  dontPatchELF = true;

  meta = with lib; {
    description = "Brother HL-2270DW CUPS driver";
    homepage = "http://welcome.solutions.brother.com/bsc/public_s/id/linux/en/index.html";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" "i686-linux" ];
    maintainers = [ ];
  };
}

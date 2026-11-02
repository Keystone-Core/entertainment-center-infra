#!/bin/bash
# Cree les VM des quatre postes du personnel (Windows 11) sur pve, dans le
# VLAN 20 (sans tag sur vmbr1). Les VM sont creees eteintes et sans systeme :
# Windows s'installe ensuite a la console (docs/guides/active-directory.md).
# Une VM qui existe deja n'est pas touchee, sauf pour y inserer l'ISO.
#
# Usage, en root sur pve :
#   ./creer-postes.sh                       # VM sans ISO de Windows
#   WIN_ISO=Win11_Entreprise.iso ./creer-postes.sh   # avec l'ISO (dans local:iso)
set -euo pipefail

STOCKAGE=vm-data
VIRTIO_ISO=local:iso/virtio-win.iso
WIN_ISO=${WIN_ISO:-}

# ID = VLAN 20 suivi du dernier octet de l'adresse prevue (journal reseau 10.1).
POSTES=(
  "20101 pc-ger-01 loucas  Gerance"
  "20102 pc-rec-01 nicolas Accueil et billetterie"
  "20103 pc-sup-01 joshua  Soutien technique"
  "20104 pc-dev-01 alexy   Poste polyvalent"
)

if [ -n "$WIN_ISO" ] && ! pvesm list local --content iso | grep -q "local:iso/$WIN_ISO "; then
  echo "ISO introuvable dans local:iso : $WIN_ISO" >&2
  exit 1
fi

for p in "${POSTES[@]}"; do
  read -r id nom compte role <<< "$p"
  if qm status "$id" >/dev/null 2>&1; then
    echo "existe deja : $id $nom"
  else
    qm create "$id" \
      --name "$nom" \
      --description "Poste du personnel : $role (compte $compte), VLAN 20. Windows 11, joint a cde.lan." \
      --tags "windows;poste" \
      --ostype win11 --machine q35 --bios ovmf \
      --efidisk0 "$STOCKAGE:1,efitype=4m,pre-enrolled-keys=1,ms-cert=2023k" \
      --tpmstate0 "$STOCKAGE:1,version=v2.0" \
      --cpu host --cores 2 --memory 4096 \
      --scsihw virtio-scsi-single \
      --scsi0 "$STOCKAGE:64,discard=on,iothread=1,ssd=1" \
      --net0 virtio,bridge=vmbr1 \
      --ide0 "$VIRTIO_ISO,media=cdrom" \
      --ide2 none,media=cdrom \
      --boot "order=scsi0;ide2" \
      --agent enabled=1 \
      --onboot 0
    echo "cree : $id $nom ($role)"
  fi
  if [ -n "$WIN_ISO" ] && ! qm config "$id" | grep -q "^ide2: local:iso/$WIN_ISO,"; then
    qm set "$id" --ide2 "local:iso/$WIN_ISO,media=cdrom" >/dev/null
    echo "ISO inseree : $id $WIN_ISO"
  fi
done

# PROXMOX SCRIPT

Catatan pribadi untuk setup VM dan LXC Container Ubuntu 24.04 di Proxmox VE menggunakan script otomatis.

## Cek Ceph di Proxmox 9.2

Jalankan perintah berikut untuk memastikan status Ceph:

```bash
ceph -s
```

Jika file konfigurasi Ceph belum tersedia di `/etc/ceph`, buat folder dan link konfigurasi dari Proxmox:

```bash
mkdir -p /etc/ceph
ln -sf /etc/pve/ceph.conf /etc/ceph/ceph.conf
```

## Remove LXC Container

Ganti `{CTID}` dengan ID container yang ingin dihapus:

```bash
pct destroy {CTID}
```

Pastikan container dalam keadaan **stopped** sebelum dihapus. Untuk stop terlebih dahulu:

```bash
pct stop {CTID} && pct destroy {CTID}
```

## Remove VM / QM

Ganti `{VMID}` dengan ID VM yang ingin dihapus:

```bash
qm destroy {VMID} --destroy-unreferenced-disks 1
```

Pastikan VMID sudah benar sebelum menjalankan perintah ini karena VM akan dihapus.

## Install LXC Container Ubuntu 24.04

Jalankan script langsung dari raw GitHub:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/starbox3/PROXMOX-SCRIPT/main/ct/Ubuntu.sh)"
```

## Install VM Ubuntu 24.04

Jalankan script langsung dari raw GitHub:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/starbox3/PROXMOX-SCRIPT/main/vm/Ubuntu-24.04.sh)"
```

## Catatan

- Jalankan script dari shell node Proxmox sebagai `root`.
- Pilih `Default Settings` jika ingin resource default tetapi tetap isi hostname, username, dan password.
- Pilih `Advanced` jika ingin custom VMID, disk, CPU, RAM, bridge, VLAN, dan opsi lain.
- Pastikan storage Proxmox sudah mendukung `snippets` jika ingin Cloud-Init custom user berjalan penuh.

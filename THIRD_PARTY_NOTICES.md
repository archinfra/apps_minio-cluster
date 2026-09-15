# Third-party notices

## PGSTY SILO

This repository packages PGSTY SILO for offline deployment.

- Project: https://github.com/pgsty/silo
- Upstream base release: `RELEASE.2026-09-03T13-18-01Z`
- Packaged source commit: `1233254309b15571f101b2b26d531951ceaeef1e`
- Reason for source pin: includes the upstream SN-2026-011 security fix not present in the latest published Server release as of 2026-09-15
- License: GNU Affero General Public License v3.0 or later
- Upstream lineage: MinIO Community Server
- Documentation: https://silo.pgsty.com/

The classic SILO image built from the pinned source includes SILO license/notice
materials and the mcli client with the legacy `mc` compatibility alias. Archinfra
delivery metadata records the exact upstream commit used to produce the distributed
binary/image.

## License boundary

Applications communicating with SILO through the S3 API are separate from the
packaged SILO program in this delivery architecture. If Archinfra modifies SILO
itself, the modified corresponding source must be handled in accordance with AGPLv3.
Consult qualified counsel for product-specific licensing decisions.

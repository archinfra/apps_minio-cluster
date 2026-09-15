# Third-party notices

## PGSTY SILO

This repository can package PGSTY SILO for offline deployment.

- Project: https://github.com/pgsty/silo
- Baseline: `RELEASE.2026-09-03T13-18-01Z`
- License: GNU Affero General Public License v3.0 or later
- Upstream lineage: MinIO Community Server
- Documentation: https://silo.pgsty.com/

The SILO image includes its own license and notice materials. Archinfra delivery
artifacts must retain those materials and record the exact source tag used to
produce the distributed binary/image.

## License boundary

Applications communicating with SILO through the S3 API are separate from the
packaged SILO program in this delivery architecture. If Archinfra modifies SILO
itself, the modified corresponding source must be handled in accordance with
AGPLv3. Consult qualified counsel for product-specific licensing decisions.

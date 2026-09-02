#!/usr/bin/env python3
"""Patch docker-squash 1.2.2 to retain OCI blob paths from Docker 25+."""

from pathlib import Path

import docker_squash.image


module_path = Path(docker_squash.image.__file__)
source = module_path.read_text()
old = '''        for layer in layers:
            layer_id = layer.replace("sha256:", "")

            self.log.debug("Moving unmodified layer '%s'..." % layer_id)
            shutil.move(os.path.join(src, layer_id), dest)
'''
new = '''        for layer in layers:
            layer_path = layer if self.oci_format else layer.replace("sha256:", "")
            destination = os.path.join(dest, layer_path)

            self.log.debug("Moving unmodified layer '%s'..." % layer_path)
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            shutil.move(os.path.join(src, layer_path), destination)
'''

if old not in source:
    if new in source:
        raise SystemExit(0)
    raise SystemExit(f"Unsupported docker-squash source: {module_path}")

module_path.write_text(source.replace(old, new, 1))

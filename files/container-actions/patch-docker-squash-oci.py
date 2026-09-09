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

            # The containerd image store shares one blob between identical
            # layers (every empty layer is sha256:4f4fb700...). The first
            # reference moves the file; later references must not fail.
            if os.path.exists(destination):
                self.log.debug("Layer '%s' already moved (shared blob), skipping" % layer_path)
                continue

            self.log.debug("Moving unmodified layer '%s'..." % layer_path)
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            shutil.move(os.path.join(src, layer_path), destination)
'''

previous = '''        for layer in layers:
            layer_path = layer if self.oci_format else layer.replace("sha256:", "")
            destination = os.path.join(dest, layer_path)

            self.log.debug("Moving unmodified layer '%s'..." % layer_path)
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            shutil.move(os.path.join(src, layer_path), destination)
'''

if new in source:
    raise SystemExit(0)
if old in source:
    module_path.write_text(source.replace(old, new, 1))
elif previous in source:
    module_path.write_text(source.replace(previous, new, 1))
else:
    raise SystemExit(f"Unsupported docker-squash source: {module_path}")

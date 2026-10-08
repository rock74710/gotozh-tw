# Vendored OpenCC

The C++ source in `src/` is from [BYVoid/OpenCC](https://github.com/BYVoid/OpenCC), release `ver.1.4.2`, commit `025f371dc76b598d77384fbdab90c937471844d8`. It is compiled into the `GotozhCore` clients through Swift Package Manager. The local `GotozhOpenCC.cpp` and `include/GotozhOpenCC.h` files provide a small C interface for Swift.

The package includes only the upstream library sources needed by this app. Its `opencc_config_schema.inc` file is generated from `data/config/opencc_config.schema.json` with the upstream `data/scripts/minify_json_to_inc.py` script.

Bundled support code and licenses:

- `marisa-trie` 0.3.1, BSD-2-Clause OR LGPL-2.1-or-later, in `deps/marisa-0.3.1/`.

- `darts-clone` 0.32h, BSD-2-Clause, in `deps/darts-clone-0.32h/`.

- RapidJSON 1.1.0, MIT, in `deps/rapidjson-1.1.0/`.

The matching [OpenCC data release](https://www.npmjs.com/package/opencc-data/v/1.4.2) is bundled in `../../Sources/GotozhCore/Resources/OpenCC/` as text dictionaries and configs. `LICENSE` files remain beside their corresponding source or data, and the App package includes all license texts under `Contents/Resources/OpenCC-Licenses/`.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GotozhNative",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GotozhCore", targets: ["GotozhCore"]),
        .executable(name: "gotozh", targets: ["GotozhCLI"]),
        .executable(name: "GotozhChecks", targets: ["GotozhChecks"]),
    ],
    targets: [
        .target(
            name: "GotozhCore",
            dependencies: ["OpenCCNative"],
            resources: [
                .copy("Resources/manual-dictionary.json"),
                .copy("Resources/OpenCC"),
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .target(
            name: "OpenCCNative",
            path: "Vendor/OpenCC",
            sources: [
                "src/BinaryDict.cpp", "src/Config.cpp", "src/Conversion.cpp",
                "src/ConversionAmbiguities.cpp", "src/ConversionCandidates.cpp",
                "src/ConversionChain.cpp", "src/Converter.cpp", "src/Dict.cpp",
                "src/DictConverter.cpp", "src/DictEntry.cpp", "src/DictGroup.cpp",
                "src/DartsDict.cpp", "src/Lexicon.cpp", "src/MarisaDict.cpp",
                "src/MaxMatchSegmentation.cpp", "src/PhraseExtract.cpp",
                "src/PipelineConverter.cpp", "src/PluginSegmentation.cpp",
                "src/PrefixMatch.cpp", "src/ResourceProvider.cpp",
                "src/SerializableDict.cpp", "src/SerializedValues.cpp",
                "src/SimpleConverter.cpp", "src/SingleStageConverter.cpp",
                "src/Segmentation.cpp", "src/TextDict.cpp",
                "src/UTF8StringSlice.cpp", "src/UTF8Util.cpp",
                "src/GotozhOpenCC.cpp",
                "deps/marisa-0.3.1/lib/marisa/agent.cc",
                "deps/marisa-0.3.1/lib/marisa/keyset.cc",
                "deps/marisa-0.3.1/lib/marisa/trie.cc",
                "deps/marisa-0.3.1/lib/marisa/grimoire/io/mapper.cc",
                "deps/marisa-0.3.1/lib/marisa/grimoire/io/reader.cc",
                "deps/marisa-0.3.1/lib/marisa/grimoire/io/writer.cc",
                "deps/marisa-0.3.1/lib/marisa/grimoire/trie/louds-trie.cc",
                "deps/marisa-0.3.1/lib/marisa/grimoire/trie/tail.cc",
                "deps/marisa-0.3.1/lib/marisa/grimoire/vector/bit-vector.cc",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("deps/darts-clone-0.32h/include"),
                .headerSearchPath("deps/marisa-0.3.1/include"),
                .headerSearchPath("deps/marisa-0.3.1/lib"),
                .headerSearchPath("deps/rapidjson-1.1.0/include"),
                .define("Opencc_BUILT_AS_STATIC"),
            ]
        ),
        .executableTarget(
            name: "GotozhCLI",
            dependencies: ["GotozhCore"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .executableTarget(
            name: "GotozhChecks",
            dependencies: ["GotozhCore"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ],
    cxxLanguageStandard: .cxx20
)

// macOS 視窗版只在 macOS 建置；Windows 只建置核心與 gotozh 命令列工具。
#if os(macOS)
package.products.append(.executable(name: "GotozhMac", targets: ["GotozhMac"]))
package.targets.append(
    .executableTarget(
        name: "GotozhMac",
        dependencies: ["GotozhCore"],
        swiftSettings: [.interoperabilityMode(.Cxx)]
    )
)
#endif

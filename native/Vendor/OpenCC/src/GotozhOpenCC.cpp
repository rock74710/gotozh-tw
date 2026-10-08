/* Gotozh bridge to the pinned OpenCC C++ API. */

#include "GotozhOpenCC.h"

#include <cstdlib>
#include <cstring>
#include <exception>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>

#include "SimpleConverter.hpp"

struct GotozhOpenCC {
  explicit GotozhOpenCC(const char *configPath, const char *dictionaryPath)
      : converter(configPath, std::vector<std::string>{dictionaryPath}) {}

  opencc::SimpleConverter converter;
};

namespace {
thread_local std::string lastError;

char *copyBuffer(const char *source, size_t length) {
  auto *copy = static_cast<char *>(std::malloc(length + 1));
  if (copy == nullptr) {
    lastError = "Unable to allocate OpenCC result buffer.";
    return nullptr;
  }
  std::memcpy(copy, source, length);
  copy[length] = '\0';
  return copy;
}

void setError(const std::exception &error) { lastError = error.what(); }
} // namespace

extern "C" GotozhOpenCC *gotozh_opencc_create(const char *config_path,
                                               const char *dictionary_path) {
  lastError.clear();
  try {
    return new GotozhOpenCC(config_path, dictionary_path);
  } catch (const std::exception &error) {
    setError(error);
  } catch (...) {
    lastError = "Unknown error while loading OpenCC.";
  }
  return nullptr;
}

extern "C" void gotozh_opencc_destroy(GotozhOpenCC *converter) {
  delete converter;
}

extern "C" char *gotozh_opencc_inspect(GotozhOpenCC *converter,
                                        const char *input,
                                        size_t input_length,
                                        size_t *output_length) {
  lastError.clear();
  if (converter == nullptr || output_length == nullptr) {
    lastError = "OpenCC converter is unavailable.";
    return nullptr;
  }

  try {
    const auto result = converter->converter.Inspect(
        std::string_view(input, input_length));
    const auto &mainStage = result.pipelineStages.empty()
                                ? result
                                : result.pipelineStages.back();
    const auto &convertedSegments = mainStage.stages.empty()
                                        ? mainStage.segments
                                        : mainStage.stages.back().segments;
    if (mainStage.segments.size() != convertedSegments.size()) {
      lastError = "OpenCC inspection returned misaligned segments.";
      return nullptr;
    }

    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    writer.StartObject();
    writer.Key("normalizedInput");
    writer.String(mainStage.input.data(),
                  static_cast<rapidjson::SizeType>(mainStage.input.size()));
    writer.Key("segments");
    writer.StartArray();
    for (size_t index = 0; index < mainStage.segments.size(); ++index) {
      const auto &from = mainStage.segments[index];
      const auto &to = convertedSegments[index];
      writer.StartObject();
      writer.Key("from");
      writer.String(from.data(), static_cast<rapidjson::SizeType>(from.size()));
      writer.Key("to");
      writer.String(to.data(), static_cast<rapidjson::SizeType>(to.size()));
      writer.EndObject();
    }
    writer.EndArray();
    writer.EndObject();

    *output_length = buffer.GetSize();
    return copyBuffer(buffer.GetString(), buffer.GetSize());
  } catch (const std::exception &error) {
    setError(error);
  } catch (...) {
    lastError = "Unknown error while running OpenCC.";
  }
  return nullptr;
}

extern "C" void gotozh_opencc_free(void *buffer) { std::free(buffer); }

extern "C" const char *gotozh_opencc_last_error(void) {
  return lastError.c_str();
}

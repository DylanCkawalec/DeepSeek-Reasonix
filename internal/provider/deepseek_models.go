package provider

import (
	"slices"
	"strings"
)

// OfficialDeepSeekVisionModel is the pinned vision SKU DeepSeek still routes to
// V4.1 Flash. It stays exported for pricing, effort and backfill keying.
const OfficialDeepSeekVisionModel = "deepseek-v4-flash-vision-exp"

// officialDeepSeekImageModels lists official DeepSeek IDs that accept image
// input natively. This is the single authority for image capability on the
// official endpoint: the capability resolver, the runtime vision gate and the
// local model catalog all consult it, so a new SKU is added in one place.
//
// deepseek-v4-flash and the beta alias are routed to V4.1 Flash for now; drop
// the alias once the vendor closes that transition window.
// OfficialDeepSeekV41FlashModel is the terminal selector for DeepSeek-V4.1-Flash.
// The vendor's request id remains deepseek-flash; OfficialDeepSeekWireModel
// rewrites this selector only on the official host.
const OfficialDeepSeekV41FlashModel = "deepseek-v4.1-flash"

var officialDeepSeekImageModels = []string{
	"deepseek-flash",
	OfficialDeepSeekV41FlashModel,
	"deepseek-v4.1-flash-expires-on-0910",
	"deepseek-v4-flash",
	OfficialDeepSeekVisionModel,
}

// IsOfficialDeepSeekImageModel reports whether model is an official DeepSeek SKU
// with native image input. Matching is case-insensitive and trims space.
func IsOfficialDeepSeekImageModel(model string) bool {
	model = strings.TrimSpace(model)
	return slices.ContainsFunc(officialDeepSeekImageModels, func(candidate string) bool {
		return strings.EqualFold(candidate, model)
	})
}

// IsOfficialDeepSeekTextModel identifies known text-only models, not future
// SKUs. It gates the official endpoint's hard image block, so a model must stay
// listed until the vendor confirms it accepts images.
// OfficialDeepSeekWireModel maps the terminal V4.1 selector onto the id the
// DeepSeek API accepts. The mixed-case beta alias keeps its lowercase wire id.
// Every other id, including gateway-specific names, is unchanged. Callers must
// apply this only for the official api.deepseek.com host.
func OfficialDeepSeekWireModel(model string) string {
	switch model {
	case "DeepSeek-V4.1-Flash-Expires-On-0910":
		return "deepseek-v4.1-flash-expires-on-0910"
	case OfficialDeepSeekV41FlashModel:
		return "deepseek-flash"
	default:
		return model
	}
}

func IsOfficialDeepSeekTextModel(model string) bool {
	switch strings.ToLower(strings.TrimSpace(model)) {
	case "deepseek-v4-pro":
		return true
	}
	return false
}

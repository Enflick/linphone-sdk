#include "mswebrtc_cpu_policy.h"

namespace mswebrtc {

SoftwareAecPolicy GetSoftwareAecPolicy(bool is_x86_family, const CpuFeatureQuery &query) {
	if (!is_x86_family) {
		return SoftwareAecPolicy::kSupported;
	}

	if ((query(webrtc::kAVX2) == 0) || (query(webrtc::kFMA3) == 0)) {
		return SoftwareAecPolicy::kBypassRequired;
	}

	return SoftwareAecPolicy::kSupported;
}

} // namespace mswebrtc

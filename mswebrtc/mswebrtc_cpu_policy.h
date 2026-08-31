#ifndef MSWEBRTC_CPU_POLICY_H_
#define MSWEBRTC_CPU_POLICY_H_

#include <functional>

#include "rtc_base/system/arch.h"
#include "system_wrappers/include/cpu_features_wrapper.h"

namespace mswebrtc {

using CpuFeatureQuery = std::function<int(webrtc::CPUFeature)>;

enum class SoftwareAecPolicy {
	kBypassRequired,
	kSupported,
};

SoftwareAecPolicy GetSoftwareAecPolicy(bool is_x86_family, const CpuFeatureQuery &query);

inline SoftwareAecPolicy GetSoftwareAecPolicy() {
#if defined(WEBRTC_ARCH_X86_FAMILY)
	return GetSoftwareAecPolicy(true, webrtc::GetCPUInfo);
#else
	return GetSoftwareAecPolicy(false, webrtc::GetCPUInfo);
#endif
}

} // namespace mswebrtc

#endif // MSWEBRTC_CPU_POLICY_H_

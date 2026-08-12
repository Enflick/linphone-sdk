import linphone

public struct LinphoneSdkInfos {
	public static let version = "5.5.13-pre.28+a69177bc6d"
	public static let branch = "remotes/origin/main"
}

public extension Core {
	/// Returns the active locally managed conference, if one exists.
	@available(*, deprecated, message: "Use Call.conference or searchConference() instead")
	var conference: Conference? {
		guard let cObject = getCobject, let conference = linphone_core_get_conference(cObject) else {
			return nil
		}
		return Conference.getSwiftObject(cObject: conference)
	}

	/// Reports whether Linphone's native audio session is active.
	var isAudioSessionActive: Bool {
		guard let cObject = getCobject else {
			return false
		}
		return linphone_core_is_audio_session_active(cObject) != 0
	}
}

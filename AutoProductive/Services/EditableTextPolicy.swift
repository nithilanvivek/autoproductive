import ApplicationServices

enum EditableTextPolicy {
    static func allows(role: String?, editable: Bool?, valueSettable: Bool,
                       readOnly: Bool?, enabled: Bool?, secure: Bool) -> Bool {
        guard !secure, enabled != false, readOnly != true, editable != false else { return false }
        guard let role, [kAXTextFieldRole, kAXTextAreaRole, kAXGroupRole, "AXWebArea"].contains(role) else { return false }
        // Web editors can expose a Group/WebArea with a writable value instead
        // of a native text role. Require positive evidence of editability.
        return editable == true || valueSettable
    }
}

//
//  ToolSession.swift
//  Photon
//

/// Which tool a photo has open, and what that tool is working on.
///
/// One value rather than a draft each, because two drafts could disagree about
/// which tool was open — and every path through the tool's life had to reconcile
/// them by hand: open, close, switch, apply, cancel, undo, redo, change photo,
/// load folder. With one value, "a crop being dragged and a grade being dragged
/// at once" is not a state the type can be in.
///
/// The *panel* is deliberately not in here. Which panel a window is showing is the
/// window's business (``EditorViewModel/openTool``), and it is a different
/// question: the colour panel stays open across photos, and opening it costs
/// nothing until a slider moves — which is when a colour session begins.
nonisolated enum ToolSession: Equatable, Sendable {
    /// No tool is working on the photo.
    case none

    /// The crop tool, on the crop it is working on.
    case crop(Crop)

    /// The colour tool, on the colours it is working on.
    case colour(ColorAdjustments)

    /// The crop being worked on, or nil when the crop tool is not the one open.
    var draftCrop: Crop? {
        if case .crop(let crop) = self { return crop }
        return nil
    }

    /// The colours being worked on, or nil when the colour tool is not the one
    /// open.
    var draftColour: ColorAdjustments? {
        if case .colour(let colour) = self { return colour }
        return nil
    }

    /// The tool this is a session for.
    var tool: Tool? {
        switch self {
        case .none: nil
        case .crop: .crop
        case .colour: .color
        }
    }
}

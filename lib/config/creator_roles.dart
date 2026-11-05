/// Coarse role buckets for the creator page, matching the backend's
/// `RoleGroup` mapping exactly.
enum CreatorRoleGroup { writer, art, covers }

/// Maps a single credited role string to its [CreatorRoleGroup], or null
/// when the role isn't tracked on the creator page (e.g. "letterer",
/// "editor"). Case-insensitive and trims whitespace.
CreatorRoleGroup? roleGroup(String role) {
  switch (role.trim().toLowerCase()) {
    case 'writer':
      return CreatorRoleGroup.writer;
    case 'penciler':
    case 'penciller':
    case 'inker':
    case 'colorist':
    case 'artist':
      return CreatorRoleGroup.art;
    case 'cover':
      return CreatorRoleGroup.covers;
    default:
      return null;
  }
}

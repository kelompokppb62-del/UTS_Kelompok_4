import 'dart:typed_data';

class WorkSubmission {
  const WorkSubmission(this.notes, this.discordUrl, this.proofUrl);

  final String notes;
  final String discordUrl;
  final String? proofUrl;

  static bool validDiscord(String value) => RegExp(
    r'^https://(discord[.]gg/|discord[.]com/invite/)[a-zA-Z0-9_-]{2,100}/?$',
  ).hasMatch(value);

  static bool validHttps(String value) =>
      value.length <= 1000 &&
      RegExp(
        r'^https://[a-zA-Z0-9-]+([.][a-zA-Z0-9-]+)+([/?#][a-zA-Z0-9._~!$&()*+,;=:@%/?#-]*)?$',
      ).hasMatch(value) &&
      !value.codeUnits.any((code) => code < 32 || code == 127) &&
      Uri.tryParse(value)?.hasAuthority == true;
}

class RevisionRequest {
  const RevisionRequest(
    this.title,
    this.description,
    this.deadline,
    this.images,
  );

  final String title;
  final String description;
  final DateTime? deadline;
  final List<Uint8List> images;

  static const maxImageBytes = 150000;
}

class ProjectActivity {
  const ProjectActivity({
    required this.id,
    required this.actor,
    required this.action,
    required this.at,
    this.submission,
    this.revision,
    this.imageCount = 0,
    this.itemTitle,
  });

  final String id;
  final String actor;
  final String action;
  final DateTime at;
  final WorkSubmission? submission;
  final RevisionRequest? revision;
  final int imageCount;
  final String? itemTitle;
}

class ChecklistItem {
  const ChecklistItem(this.id, this.title, this.done);
  final String id;
  final String title;
  final bool done;
}

class ProjectMessage {
  const ProjectMessage(this.author, this.text, this.at);
  final String author;
  final String text;
  final DateTime at;
}

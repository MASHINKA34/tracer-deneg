import '../categories/category_color.dart';
import '../time/month_day.dart';
import 'json.dart';

/// Профиль участника общего бюджета — только чтение на клиенте (00-spec §8).
final class MemberProfile {
  const MemberProfile({
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    this.birthday,
  });

  factory MemberProfile.fromJson(Object? json) {
    final r = JsonReader.of(json, 'MemberProfile');
    return MemberProfile(
      userId: r.string('userId'),
      displayName: r.string('displayName'),
      avatarColor: r.enumByName('avatarColor', CategoryColor.values),
      birthday: MonthDay.fromParts(
        r.optInteger('birthdayMonth'),
        r.optInteger('birthdayDay'),
      ),
    );
  }

  final String userId;
  final String displayName;
  final CategoryColor avatarColor;

  /// День рождения (виден участникам общих бюджетов) или `null`.
  final MonthDay? birthday;

  Map<String, Object?> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'avatarColor': avatarColor.name,
    'birthdayMonth': birthday?.month,
    'birthdayDay': birthday?.day,
  };

  @override
  bool operator ==(Object other) =>
      other is MemberProfile &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.avatarColor == avatarColor &&
      other.birthday == birthday;

  @override
  int get hashCode => Object.hash(userId, displayName, avatarColor, birthday);

  /// Без имени и даты рождения: личные данные не пишем в лог.
  @override
  String toString() => 'MemberProfile($userId ${avatarColor.name})';
}

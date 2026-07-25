import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/app_settings_repository.dart';

final class LoadAppSettingsUseCase {
  const LoadAppSettingsUseCase(this._repository);

  final AppSettingsRepository _repository;

  Future<AppSettings> execute() => _repository.read();
}

final class SaveAppSettingsUseCase {
  const SaveAppSettingsUseCase(this._repository);

  final AppSettingsRepository _repository;

  Future<void> execute(AppSettings settings) => _repository.save(settings);
}

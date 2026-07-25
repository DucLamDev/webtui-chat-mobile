import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_remote_data_source.dart';

final class ProfileRepositoryImpl implements ProfileRepository {
  const ProfileRepositoryImpl(this._remote);

  final ProfileRemoteDataSource _remote;

  @override
  Future<Result<UserProfile>> me() {
    return guardResult(_remote.me);
  }

  @override
  Future<Result<UserProfile>> updateMe(UpdateProfileCommand command) {
    return guardResult(() => _remote.updateMe(command));
  }
}

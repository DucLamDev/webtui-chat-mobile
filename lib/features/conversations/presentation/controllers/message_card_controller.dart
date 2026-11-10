import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/rich_message_use_cases.dart';
import '../../domain/entities/message_card.dart';
import '../../domain/entities/rich_message.dart';

/// Một thẻ của một tin: khoá theo workspace / kênh / tin.
@immutable
final class MessageCardScope {
  const MessageCardScope({
    required this.workspaceId,
    required this.channelId,
    required this.messageId,
  });

  final String workspaceId;
  final String channelId;
  final String messageId;

  @override
  bool operator ==(Object other) =>
      other is MessageCardScope &&
      other.workspaceId == workspaceId &&
      other.channelId == channelId &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(workspaceId, channelId, messageId);
}

final messageCardControllerProvider = StateNotifierProvider.autoDispose
    .family<MessageCardController, MessageCardState, MessageCardScope>((
      ref,
      scope,
    ) {
      return MessageCardController(
        scope: scope,
        invokeAction: ref.watch(invokeMessageActionUseCaseProvider),
        submitForm: ref.watch(submitMessageFormUseCaseProvider),
        loadInteractions: ref.watch(loadMyMessageInteractionsUseCaseProvider),
        decideApproval: ref.watch(decideApprovalUseCaseProvider),
      );
    });

@immutable
final class MessageCardState {
  const MessageCardState({
    this.interactionsLoaded = false,
    this.loadingInteractions = false,
    this.invokedActionIds = const {},
    this.pendingActionIds = const {},
    this.submittedForms = const {},
    this.submittingFormIds = const {},
    this.fieldErrors = const {},
    this.formErrors = const {},
    this.decidedApprovalIds = const {},
    this.pendingApprovalIds = const {},
    this.errorMessage,
    this.noticeMessage,
  });

  final bool interactionsLoaded;
  final bool loadingInteractions;

  /// Nút `callback` người này đã bấm (từ máy chủ hoặc vừa bấm).
  final Set<String> invokedActionIds;
  final Set<String> pendingActionIds;

  /// Lần gửi gần nhất của từng biểu mẫu.
  final Map<String, DateTime> submittedForms;
  final Set<String> submittingFormIds;

  /// Lỗi từng ô theo `form_id` → `field_id`.
  final Map<String, Map<String, String>> fieldErrors;

  /// Lỗi chung của biểu mẫu theo `form_id`.
  final Map<String, String> formErrors;

  final Set<String> decidedApprovalIds;
  final Set<String> pendingApprovalIds;
  final String? errorMessage;
  final String? noticeMessage;

  bool isActionLocked(String actionId) =>
      invokedActionIds.contains(actionId) ||
      pendingActionIds.contains(actionId);

  bool isApprovalLocked(String approvalId) =>
      decidedApprovalIds.contains(approvalId) ||
      pendingApprovalIds.contains(approvalId);

  MessageCardState copyWith({
    bool? interactionsLoaded,
    bool? loadingInteractions,
    Set<String>? invokedActionIds,
    Set<String>? pendingActionIds,
    Map<String, DateTime>? submittedForms,
    Set<String>? submittingFormIds,
    Map<String, Map<String, String>>? fieldErrors,
    Map<String, String>? formErrors,
    Set<String>? decidedApprovalIds,
    Set<String>? pendingApprovalIds,
    String? errorMessage,
    String? noticeMessage,
    bool clearMessages = false,
  }) {
    return MessageCardState(
      interactionsLoaded: interactionsLoaded ?? this.interactionsLoaded,
      loadingInteractions: loadingInteractions ?? this.loadingInteractions,
      invokedActionIds: invokedActionIds ?? this.invokedActionIds,
      pendingActionIds: pendingActionIds ?? this.pendingActionIds,
      submittedForms: submittedForms ?? this.submittedForms,
      submittingFormIds: submittingFormIds ?? this.submittingFormIds,
      fieldErrors: fieldErrors ?? this.fieldErrors,
      formErrors: formErrors ?? this.formErrors,
      decidedApprovalIds: decidedApprovalIds ?? this.decidedApprovalIds,
      pendingApprovalIds: pendingApprovalIds ?? this.pendingApprovalIds,
      errorMessage: clearMessages ? null : errorMessage ?? this.errorMessage,
      noticeMessage: clearMessages ? null : noticeMessage ?? this.noticeMessage,
    );
  }
}

final class MessageCardController extends StateNotifier<MessageCardState> {
  MessageCardController({
    required this.scope,
    required InvokeMessageActionUseCase invokeAction,
    required SubmitMessageFormUseCase submitForm,
    required LoadMyMessageInteractionsUseCase loadInteractions,
    required DecideApprovalUseCase decideApproval,
  }) : _invokeAction = invokeAction,
       _submitForm = submitForm,
       _loadInteractions = loadInteractions,
       _decideApproval = decideApproval,
       super(const MessageCardState());

  final MessageCardScope scope;
  final InvokeMessageActionUseCase _invokeAction;
  final SubmitMessageFormUseCase _submitForm;
  final LoadMyMessageInteractionsUseCase _loadInteractions;
  final DecideApprovalUseCase _decideApproval;

  /// Tải nút đã bấm / biểu mẫu đã gửi (một lần cho mỗi thẻ đang hiện).
  Future<void> loadInteractions({bool force = false}) async {
    if (state.loadingInteractions || (state.interactionsLoaded && !force)) {
      return;
    }
    state = state.copyWith(loadingInteractions: true);
    final result = await _loadInteractions.execute(
      workspaceId: scope.workspaceId,
      channelId: scope.channelId,
      messageId: scope.messageId,
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        final forms = {...state.submittedForms};
        for (final form in value.forms) {
          final previous = forms[form.formId];
          if (previous == null || form.submittedAt.isAfter(previous)) {
            forms[form.formId] = form.submittedAt;
          }
        }
        state = state.copyWith(
          interactionsLoaded: true,
          loadingInteractions: false,
          invokedActionIds: {
            ...state.invokedActionIds,
            for (final action in value.actions) action.actionId,
          },
          submittedForms: forms,
        );
      case FailureResult():
        // Không tải được thì vẫn cho bấm: máy chủ tự chặn bấm trùng.
        state = state.copyWith(
          interactionsLoaded: true,
          loadingInteractions: false,
        );
    }
  }

  /// Bấm nút `callback`; trả `true` khi máy chủ đã ghi nhận. Nút đang gửi hoặc
  /// đã bấm thì không gọi lại.
  Future<bool> invokeAction(MessageCardCallbackAction action) async {
    if (state.isActionLocked(action.actionId)) return false;
    state = state.copyWith(
      pendingActionIds: {...state.pendingActionIds, action.actionId},
      clearMessages: true,
    );
    final result = await _invokeAction.execute(
      workspaceId: scope.workspaceId,
      channelId: scope.channelId,
      messageId: scope.messageId,
      actionId: action.actionId,
    );
    if (!mounted) return false;
    final pending = {...state.pendingActionIds}..remove(action.actionId);
    switch (result) {
      case Success(:final value):
        state = state.copyWith(
          pendingActionIds: pending,
          invokedActionIds: {...state.invokedActionIds, action.actionId},
          noticeMessage: value.duplicate
              ? 'Bạn đã bấm nút này trước đó.'
              : 'Đã gửi: ${action.label}',
        );
        return true;
      case FailureResult(:final failure):
        state = state.copyWith(
          pendingActionIds: pending,
          errorMessage: failure.message,
        );
        return false;
    }
  }

  /// Gửi biểu mẫu; trả `true` khi máy chủ đã nhận.
  Future<bool> submitForm(
    MessageCardForm form,
    Map<String, Object?> values,
  ) async {
    final formId = form.formId;
    if (state.submittingFormIds.contains(formId) || isFormLocked(form)) {
      return false;
    }
    state = state.copyWith(
      submittingFormIds: {...state.submittingFormIds, formId},
      fieldErrors: {...state.fieldErrors}..remove(formId),
      formErrors: {...state.formErrors}..remove(formId),
      clearMessages: true,
    );
    final result = await _submitForm.execute(
      workspaceId: scope.workspaceId,
      channelId: scope.channelId,
      messageId: scope.messageId,
      form: form,
      values: values,
    );
    if (!mounted) return false;
    final submitting = {...state.submittingFormIds}..remove(formId);
    switch (result) {
      case Success(:final value):
        state = state.copyWith(
          submittingFormIds: submitting,
          submittedForms: {...state.submittedForms, formId: value.submittedAt},
        );
        return true;
      case FailureResult(:final failure):
        final cause = failure.cause;
        final fields = cause is MessageFormFieldErrors
            ? cause.fields
            : const <String, String>{};
        state = state.copyWith(
          submittingFormIds: submitting,
          fieldErrors: fields.isEmpty
              ? null
              : {...state.fieldErrors, formId: fields},
          formErrors: {...state.formErrors, formId: failure.message},
        );
        if (failure.code == 'FORM_ALREADY_SUBMITTED') {
          // Đã gửi từ thiết bị khác: tải lại để biết giờ gửi và khoá biểu mẫu.
          await loadInteractions(force: true);
        }
        return false;
    }
  }

  /// Biểu mẫu chỉ cho gửi một lần và người này đã gửi.
  bool isFormLocked(MessageCardForm form) =>
      !form.allowMultiple && state.submittedForms.containsKey(form.formId);

  Future<bool> decideApproval(MessageCardApprovalAction action) async {
    if (state.isApprovalLocked(action.approvalId)) return false;
    state = state.copyWith(
      pendingApprovalIds: {...state.pendingApprovalIds, action.approvalId},
      clearMessages: true,
    );
    final result = await _decideApproval.execute(
      workspaceId: scope.workspaceId,
      approvalId: action.approvalId,
      decision: action.decision,
    );
    if (!mounted) return false;
    final pending = {...state.pendingApprovalIds}..remove(action.approvalId);
    switch (result) {
      case Success():
        state = state.copyWith(
          pendingApprovalIds: pending,
          decidedApprovalIds: {...state.decidedApprovalIds, action.approvalId},
          noticeMessage: action.decision == MessageCardApprovalDecision.approve
              ? 'Đã gửi quyết định đồng ý.'
              : 'Đã gửi quyết định từ chối.',
        );
        return true;
      case FailureResult(:final failure):
        state = state.copyWith(
          pendingApprovalIds: pending,
          errorMessage: failure.kind == FailureKind.unknown
              ? 'Chưa gửi được quyết định. Vui lòng thử lại.'
              : failure.message,
        );
        return false;
    }
  }

  void clearMessages() {
    if (state.errorMessage == null && state.noticeMessage == null) return;
    state = state.copyWith(clearMessages: true);
  }
}

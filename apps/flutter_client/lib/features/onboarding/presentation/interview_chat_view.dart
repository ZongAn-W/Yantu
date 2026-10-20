import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../domain/onboarding_session.dart';
import 'interview_voice.dart';
import 'learning_context_view.dart';

/// 与旧版访谈页一致的题量上限与生成门槛，聊天样式只改变呈现方式。
const maxInterviewAnswers = 50;
const minAnswersToGenerate = 5;

/// 微信聊天页配色：从语义令牌派生。
///
/// 浅色下保持原微信配色（像素与旧版一致）；暗色下改用 surface / surfaceMuted /
/// border / text 等语义角色，保证气泡、输入条与系统提示在 Dense Graphite 下可读。
abstract final class InterviewChatColors {
  static Color page(PlannerTokens tokens) =>
      tokens.isDark ? tokens.canvas : const Color(0xffededed);

  static Color receivedBubble(PlannerTokens tokens) => tokens.surface;

  static Color sentBubble(PlannerTokens tokens) =>
      tokens.isDark ? tokens.accentSoft : const Color(0xff95ec69);

  static Color inputBar(PlannerTokens tokens) =>
      tokens.isDark ? tokens.surfaceMuted : const Color(0xfff7f7f7);

  static Color divider(PlannerTokens tokens) =>
      tokens.isDark ? tokens.border : const Color(0xffe3e3e3);

  static Color sendEnabled(PlannerTokens tokens) =>
      tokens.isDark ? tokens.success : const Color(0xff07c160);

  static Color sendDisabled(PlannerTokens tokens) =>
      tokens.isDark ? tokens.borderStrong : const Color(0xffc8e6d2);

  static Color sendDisabledInk(PlannerTokens tokens) =>
      tokens.isDark ? tokens.subtle : Colors.white;

  static Color systemText(PlannerTokens tokens) =>
      tokens.isDark ? tokens.subtle : const Color(0xff8a8a8a);

  static Color bubbleInk(PlannerTokens tokens) =>
      tokens.isDark ? tokens.text : const Color(0xff1a1a1a);

  static Color bubbleBorder(PlannerTokens tokens) =>
      tokens.isDark ? tokens.border : const Color(0xffe6e6e6);

  static Color listeningFill(PlannerTokens tokens) =>
      tokens.isDark ? tokens.accentSoft : const Color(0xffe4f4e8);

  static Color avatarInk(PlannerTokens tokens) =>
      tokens.isDark ? tokens.accentOn : Colors.white;
}

/// 目标访谈的微信聊天式页面：左侧是「对方」的提问，右侧是自己的回答，
/// 底部是文字输入与语音输入。不再提供任何选择题选项。
class InterviewChatView extends StatefulWidget {
  const InterviewChatView({
    required this.session,
    required this.busy,
    required this.thinking,
    required this.error,
    required this.planChanged,
    required this.embedded,
    required this.onAnswer,
    required this.onGenerate,
    required this.onRestart,
    required this.onReload,
    required this.onRefreshPlan,
    required this.onAction,
    super.key,
  });

  final OnboardingSession session;

  /// 正在提交/生成，按钮与输入框暂时不可用。
  final bool busy;

  /// 正在等待 AI 返回下一问；聊天里显示「对方正在输入中」。
  final bool thinking;
  final String? error;
  final bool planChanged;
  final bool embedded;
  final Future<bool> Function(String answer) onAnswer;
  final Future<bool> Function() onGenerate;
  final VoidCallback onRestart;
  final VoidCallback onReload;
  final VoidCallback onRefreshPlan;
  final Future<bool> Function(JsonMap action) onAction;

  @override
  State<InterviewChatView> createState() => _InterviewChatViewState();
}

class _InterviewChatViewState extends State<InterviewChatView> {
  final _form = GlobalKey<FormState>();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _voice = InterviewVoiceInput();

  bool _voiceMode = false;
  bool _listening = false;
  String _interim = '';
  String? _pendingAnswer;
  String? _questionKey;

  @override
  void initState() {
    super.initState();
    _questionKey = _sessionQuestionKey(widget.session);
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(covariant InterviewChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _sessionQuestionKey(widget.session);
    if (nextKey != _questionKey) {
      _questionKey = nextKey;
      // 新问题到达后清空刚才的临时气泡与输入框；失败重试时问题不变，草稿保留。
      _pendingAnswer = null;
      _interim = '';
      if (!_listening) _input.clear();
    }
    if (nextKey != _sessionQuestionKey(oldWidget.session) ||
        widget.thinking != oldWidget.thinking ||
        widget.error != oldWidget.error ||
        widget.session.answers.length != oldWidget.session.answers.length) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _voice.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _sessionQuestionKey(OnboardingSession session) =>
      '${session.answers.length}|${session.question}';

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    if (widget.busy) return;
    final text = _input.text.trim();
    if (text.isEmpty) {
      _form.currentState?.validate();
      return;
    }
    setState(() => _pendingAnswer = text);
    final accepted = await widget.onAnswer(text);
    if (!mounted) return;
    setState(() {
      // 成功后清空输入；失败保留在输入框里，方便直接重试。
      _pendingAnswer = null;
      if (accepted) _input.clear();
    });
    if (accepted) _focus.requestFocus();
    _scrollToBottom();
  }

  Future<void> _generate() async {
    if (widget.busy) return;
    final generated = await widget.onGenerate();
    if (!mounted) return;
    if (generated) _input.clear();
    _scrollToBottom();
  }

  Future<void> _startListening() async {
    if (_listening || widget.busy) return;
    if (!InterviewVoiceInput.isSupported) {
      _showVoiceMessage('当前环境暂不支持语音输入，请直接输入文字');
      return;
    }
    if (!_voiceMode) setState(() => _voiceMode = true);
    setState(() => _listening = true);
    final started = await _voice.start(
      onText: (text, isFinal) {
        if (!mounted) return;
        setState(() => _interim = text.trim());
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _interim = '';
        });
        _showVoiceMessage(message);
      },
      onDone: () {
        if (!mounted) return;
        final text = _interim.trim();
        setState(() {
          _listening = false;
          _interim = '';
        });
        if (text.isEmpty) return;
        final existing = _input.text.trim();
        _input.text = existing.isEmpty ? text : '$existing $text';
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        setState(() => _voiceMode = false);
        _focus.requestFocus();
      },
    );
    if (!mounted) return;
    if (!started) {
      setState(() => _listening = false);
      _showVoiceMessage('语音输入启动失败，请重试或直接输入文字');
    }
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    setState(() => _listening = false);
    await _voice.stop();
  }

  void _showVoiceMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openLearningContext() {
    final session = widget.session;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: LearningContextView(
            session: session,
            busy: widget.busy,
            onAction: (action) async {
              final ok = await widget.onAction(action);
              if (ok && sheetContext.mounted) Navigator.of(sheetContext).pop();
              return ok;
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final answers = widget.session.answers;
    final reachedLimit = answers.length >= maxInterviewAnswers;
    return ColoredBox(
      color: InterviewChatColors.page(tokens),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              children: [
                _header(answers.length, reachedLimit),
                Expanded(child: _conversation(answers, reachedLimit)),
                _composer(answers, reachedLimit),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int answerCount, bool reachedLimit) {
    final tokens = context.tokens;
    return Container(
      color: tokens.surface,
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          const _ChatAvatar(friend: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '不白学助手',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // 窄屏时只保留题号，避免标题行拥挤换行或溢出。
                    final showCount = constraints.maxWidth >= 150;
                    return Row(
                      children: [
                        Flexible(
                          child: Text(
                            reachedLimit ? '访谈已达到上限' : '第 ${answerCount + 1} 问',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        if (!reachedLimit && showCount)
                          Flexible(
                            child: Text(
                              ' · 已答 $answerCount 问',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '学习情况与官方资料',
            onPressed: widget.busy ? null : _openLearningContext,
            icon: const Icon(Icons.fact_check_outlined, size: 20),
          ),
          TextButton.icon(
            onPressed: widget.busy ? null : widget.onRestart,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('重新访谈'),
          ),
        ],
      ),
    );
  }

  Widget _conversation(List<InterviewAnswer> answers, bool reachedLimit) {
    final messages = <Widget>[];
    if (widget.session.replanning) {
      messages.add(_systemText('新计划确认前，当前计划保持生效。'));
    }
    for (var i = 0; i < answers.length; i++) {
      messages.add(
        _receivedBubble(
          answers[i].question,
          key: ValueKey('interview-question-$i'),
        ),
      );
      messages.add(
        _sentBubble(answers[i].answer, key: ValueKey('interview-answer-$i')),
      );
    }
    if (reachedLimit) {
      messages
        ..add(_systemText('已达到 $maxInterviewAnswers 题上限'))
        ..add(_systemText('请根据当前回答生成学习事项，或重新访谈后再继续补充。'));
    } else {
      messages.add(
        _receivedBubble(
          widget.session.question,
          key: ValueKey('interview-question-${answers.length}'),
        ),
      );
    }
    if (_pendingAnswer != null) {
      messages.add(
        _sentBubble(_pendingAnswer!, key: const ValueKey('interview-sending')),
      );
    }
    if (widget.thinking) messages.add(const _TypingBubble());
    final researchMessage = _researchMessage();
    if (researchMessage != null) messages.add(researchMessage);
    if (widget.error != null) messages.add(_errorNotice());
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: messages,
    );
  }

  Widget? _researchMessage() {
    final tokens = context.tokens;
    final research = widget.session.research;
    final status = research['status'] as String? ?? 'idle';
    final message = research['message'] as String? ?? '';
    if (status == 'idle' || message.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (status == 'pending')
            const PlannerSpinner(size: 12)
          else
            Icon(
              Icons.info_outline,
              size: 13,
              color: InterviewChatColors.systemText(tokens),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: InterviewChatColors.systemText(tokens),
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorNotice() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: PlannerNotice(widget.error!, tone: PlannerNoticeTone.error),
    );
  }

  Widget _composer(List<InterviewAnswer> answers, bool reachedLimit) {
    final tokens = context.tokens;
    final showsGenerate =
        answers.length >= minAnswersToGenerate || reachedLimit;
    return Container(
      decoration: BoxDecoration(
        color: InterviewChatColors.inputBar(tokens),
        border: Border(
          top: BorderSide(color: InterviewChatColors.divider(tokens)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.error != null && widget.planChanged)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.busy ? null : widget.onRefreshPlan,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('更新当前计划进度，保留草稿'),
              ),
            ),
          if (widget.error != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.busy ? null : widget.onReload,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新读取已保存进度'),
              ),
            ),
          if (showsGenerate)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                child: OutlinedButton.icon(
                  onPressed: widget.busy ? null : _generate,
                  icon: const Icon(Icons.checklist_rtl, size: 18),
                  label: const Text('根据当前回答生成事项'),
                ),
              ),
            ),
          if (!reachedLimit && (_listening || _interim.isNotEmpty))
            _estimatedVoiceHint(),
          if (reachedLimit)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '已达到 $maxInterviewAnswers 题上限，请先生成事项或重新访谈。',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.muted),
              ),
            )
          else if (_voiceMode)
            _voiceBar()
          else
            _textBar(),
        ],
      ),
    );
  }

  Widget _textBar() {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: '语音输入',
          onPressed: widget.busy
              ? null
              : () => setState(() => _voiceMode = true),
          icon: const Icon(Icons.mic_none),
        ),
        Expanded(
          child: Form(
            key: _form,
            child: TextFormField(
              key: const ValueKey('interview-answer-input'),
              controller: _input,
              focusNode: _focus,
              enabled: !widget.busy,
              minLines: 1,
              maxLines: 4,
              maxLength: 4000,
              textInputAction: TextInputAction.send,
              onFieldSubmitted: (_) => _send(),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请先填写回答' : null,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: '输入你的回答…',
                isDense: true,
                counterText: '',
                filled: true,
                fillColor: tokens.surface,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide.none,
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide.none,
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _sendButton(),
      ],
    );
  }

  Widget _voiceBar() {
    final tokens = context.tokens;
    return Row(
      children: [
        IconButton(
          tooltip: '切换文字输入',
          onPressed: widget.busy
              ? null
              : () => setState(() => _voiceMode = false),
          icon: const Icon(Icons.keyboard_alt_outlined),
        ),
        Expanded(
          child: Semantics(
            button: true,
            label: '按住 说话',
            child: Listener(
              onPointerDown: (_) => _startListening(),
              onPointerUp: (_) => _stopListening(),
              onPointerCancel: (_) => _stopListening(),
              child: Container(
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _listening
                      ? InterviewChatColors.listeningFill(tokens)
                      : tokens.surface,
                  border: Border.all(
                    color: _listening
                        ? InterviewChatColors.sendEnabled(tokens)
                        : InterviewChatColors.divider(tokens),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _listening ? '松开 结束' : '按住 说话',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _sendButton(),
      ],
    );
  }

  Widget _sendButton() {
    final tokens = context.tokens;
    final canSend = !widget.busy;
    return FilledButton(
      key: const ValueKey('interview-send'),
      onPressed: canSend ? _send : null,
      style: FilledButton.styleFrom(
        backgroundColor: InterviewChatColors.sendEnabled(tokens),
        disabledBackgroundColor: InterviewChatColors.sendDisabled(tokens),
        disabledForegroundColor: InterviewChatColors.sendDisabledInk(tokens),
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: const Text('发送'),
    );
  }

  Widget _estimatedVoiceHint() {
    if (!_listening && _interim.isEmpty) return const SizedBox.shrink();
    final tokens = context.tokens;
    return Container(
      color: InterviewChatColors.inputBar(tokens),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          Icon(Icons.graphic_eq, size: 16, color: tokens.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _interim.isEmpty ? '正在听，请说话…' : _interim,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _receivedBubble(String text, {Key? key}) =>
      _bubble(key: key, text: text, mine: false);

  Widget _sentBubble(String text, {Key? key}) =>
      _bubble(key: key, text: text, mine: true);

  Widget _bubble({Key? key, required String text, required bool mine}) {
    final tokens = context.tokens;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: mine
            ? InterviewChatColors.sentBubble(tokens)
            : InterviewChatColors.receivedBubble(tokens),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(8),
          topRight: const Radius.circular(8),
          bottomLeft: Radius.circular(mine ? 8 : 2),
          bottomRight: Radius.circular(mine ? 2 : 8),
        ),
        border: mine
            ? null
            : Border.all(
                color: InterviewChatColors.bubbleBorder(tokens),
                width: 0.6,
              ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: InterviewChatColors.bubbleInk(tokens),
          fontSize: 15,
          height: 1.4,
        ),
      ),
    );
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!mine) ...[
            const _ChatAvatar(friend: true),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: bubble,
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 8),
            const _ChatAvatar(friend: false),
          ],
        ],
      ),
    );
  }

  Widget _systemText(String text) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: InterviewChatColors.systemText(tokens),
          fontSize: 12.5,
        ),
      ),
    );
  }
}

/// 头像：对方用应用图标，自己用「我」。
class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({required this.friend});
  final bool friend;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: friend ? tokens.success : tokens.accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(
        friend ? Icons.auto_awesome : Icons.person,
        size: 20,
        color: InterviewChatColors.avatarInk(tokens),
      ),
    );
  }
}

/// 「对方正在输入中」气泡：三个固定明暗的圆点加文字。
///
/// 这是「等待 AI 回复」的状态提示，不是装饰动画：圆点不再循环闪烁，避免
/// 无限动画在 reduced-motion 下仍持续，并让测试的 pumpAndSettle 可以收敛。
class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  /// 三个圆点保留 0.35/0.55/0.75 的固定透明度，静态下依然可区分。
  static const List<double> _dotOpacities = [0.35, 0.55, 0.75];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ChatAvatar(friend: true),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: InterviewChatColors.receivedBubble(tokens),
              border: Border.all(
                color: InterviewChatColors.bubbleBorder(tokens),
                width: 0.6,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
                bottomLeft: Radius.circular(2),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Semantics(
              liveRegion: true,
              label: '对方正在输入中',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final opacity in _dotOpacities)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: tokens.muted,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    '对方正在输入中',
                    style: TextStyle(color: tokens.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

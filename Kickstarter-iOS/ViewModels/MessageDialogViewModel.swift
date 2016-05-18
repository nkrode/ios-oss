import KsApi
import Library
import Models
import Prelude
import ReactiveCocoa
import Result

internal protocol MessageDialogViewModelInputs {
  /// Call when the message text changes.
  func bodyTextChanged(body: String)

  /// Call when the cancel button is pressed.
  func cancelButtonPressed()

  /// Call with the message thread provided to the view.
  func configureWith(messageThread messageThread: MessageThread, context: Koala.MessageDialogContext)

  /// Call when the post button is pressed.
  func postButtonPressed()

  /// Call when the view loads.
  func viewDidLoad()
}

internal protocol MessageDialogViewModelOutputs {
  /// Emits a boolean that determines if the keyboard is shown or not.
  var keyboardIsVisible: Signal<Bool, NoError> { get }

  /// Emits a boolean that determines if the loading view is hidden or not.
  var loadingViewIsHidden: Signal<Bool, NoError> { get }

  /// Emits the message just successfully posted.
  var notifyPresenterCommentWasPostedSuccesfully: Signal<Message, NoError> { get }

  /// Emits when the dialog should be dismissed.
  var notifyPresenterDialogWantsDismissal: Signal<(), NoError> { get }

  /// Emits a boolean that determines if the post button is enabled.
  var postButtonEnabled: Signal<Bool, NoError> { get }

  /// Emits the recipient's name.
  var recipientName: Signal<String, NoError> { get }

  /// Emits a string that should be alerted to the user.
  var showAlertMessage: Signal<String, NoError> { get }
}

internal protocol MessageDialogViewModelType {
  var inputs: MessageDialogViewModelInputs { get }
  var outputs: MessageDialogViewModelOutputs { get }
}

internal final class MessageDialogViewModel: MessageDialogViewModelType, MessageDialogViewModelInputs,
MessageDialogViewModelOutputs {

  // swiftlint:disable function_body_length
  internal init() {
    let messageThread = self.configData.producer.ignoreNil()
      .map { messageThread, _ in messageThread }
      .takeWhen(self.viewDidLoadProperty.signal)

    let isLoading = MutableProperty(false)

    let bodyIsPresent = self.bodyTextChangedProperty.signal.ignoreNil()
      .map { !$0.stringByTrimmingCharactersInSet(.whitespaceCharacterSet()).characters.isEmpty }
      .skipRepeats()

    self.postButtonEnabled = Signal.merge(
      self.viewDidLoadProperty.signal.take(1).mapConst(false),
      bodyIsPresent
    )

    let sendMessageResult = combineLatest(
      self.bodyTextChangedProperty.signal.ignoreNil(),
      messageThread
      )
      .takeWhen(self.postButtonPressedProperty.signal)
      .switchMap { body, messageThread in
        AppEnvironment.current.apiService.sendMessage(body: body, toThread: messageThread)
          .delay(AppEnvironment.current.apiDelayInterval, onScheduler: AppEnvironment.current.scheduler)
          .on(started: { isLoading.value = true },
            terminated: { isLoading.value = false })
          .materialize()
    }

    self.notifyPresenterCommentWasPostedSuccesfully = sendMessageResult.values()

    self.showAlertMessage = sendMessageResult.errors()
      .map {
        $0.errorMessages.first ??
          localizedString(key: "messages.dialog.generic_error",
            defaultValue: "Sorry, your message could not be posted.")
    }

    self.notifyPresenterDialogWantsDismissal = Signal.merge(
      self.cancelButtonPressedProperty.signal,
      self.notifyPresenterCommentWasPostedSuccesfully.ignoreValues()
    )

    self.loadingViewIsHidden = Signal.merge(
      self.viewDidLoadProperty.signal.take(1).mapConst(true),
      isLoading.signal.map(negate)
    )

    self.recipientName = messageThread.take(1)
      .map { $0.participant.name }

    self.keyboardIsVisible = Signal.merge(
      self.viewDidLoadProperty.signal.mapConst(true),
      self.notifyPresenterDialogWantsDismissal.mapConst(false)
    )

    self.configData.signal.ignoreNil()
      .map { ($0.project, $1) }
      .takeWhen(self.notifyPresenterCommentWasPostedSuccesfully)
      .observeNext { project, context in
        AppEnvironment.current.koala.trackMessageSent(project: project, context: context)
    }
  }
  // swiftlint:enable function_body_length

  private let bodyTextChangedProperty = MutableProperty<String?>(nil)
  internal func bodyTextChanged(body: String) {
    self.bodyTextChangedProperty.value = body
  }
  private let cancelButtonPressedProperty = MutableProperty()
  internal func cancelButtonPressed() {
    self.cancelButtonPressedProperty.value = ()
  }
  private let configData = MutableProperty<(MessageThread, Koala.MessageDialogContext)?>(nil)
  internal func configureWith(messageThread messageThread: MessageThread,
                                            context: Koala.MessageDialogContext) {
    self.configData.value = (messageThread, context)
  }
  private let postButtonPressedProperty = MutableProperty()
  internal func postButtonPressed() {
    self.postButtonPressedProperty.value = ()
  }
  private let viewDidLoadProperty = MutableProperty()
  internal func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  internal let loadingViewIsHidden: Signal<Bool, NoError>
  internal let postButtonEnabled: Signal<Bool, NoError>
  internal let notifyPresenterDialogWantsDismissal: Signal<(), NoError>
  internal let notifyPresenterCommentWasPostedSuccesfully: Signal<Message, NoError>
  internal let recipientName: Signal<String, NoError>
  internal let keyboardIsVisible: Signal<Bool, NoError>
  internal let showAlertMessage: Signal<String, NoError>

  internal var inputs: MessageDialogViewModelInputs { return self }
  internal var outputs: MessageDialogViewModelOutputs { return self }
}
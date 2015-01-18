import UIKit

class TextFieldValidator<T> {
  typealias SyncValidator = String -> Try<T>
  typealias AsyncValidator = String -> Future<T>
  typealias OnValidatedCallback = Try<T> -> Void

  private let validator: AsyncValidator
  private let onValidated: OnValidatedCallback

  private let queue = dispatch_queue_create(
    Config.BundleIdentifier + ".TextFieldValidator",
    DISPATCH_QUEUE_SERIAL)

  private let validBorderWidth: CGFloat
  private let validBorderColor: CGColor

  private var delegate: OnTextChangeTextFieldDelegate!
  private weak var textField: UITextField!

  private let switcher: (Future<T> -> Future<T>) = QueueExecution.makeSwitchLatest()
  private let debouncer: (String -> Void)!

  init(
    textField: UITextField,
    asyncValidator: AsyncValidator,
    onValidated: OnValidatedCallback)
  {
    self.textField = textField
    self.validator = asyncValidator
    self.onValidated = onValidated

    validBorderWidth = textField.layer.borderWidth
    validBorderColor = textField.layer.borderColor

    debouncer = QueueExecution.makeDebouncer(Config.UI.ValidationThrottleInMS, queue) { self.validate($0) }

    delegate = OnTextChangeTextFieldDelegate() { text, replacement, range in
      QueueExecution.async(self.queue) {
        let newText = self.change(text: text, replacement: replacement, range: range)
        self.debouncer(newText)
      }
    }

    textField.delegate = delegate
  }

  convenience init(
    textField: UITextField,
    syncValidator: SyncValidator,
    onValidated: OnValidatedCallback)
  {
    self.init(
      textField: textField,
      asyncValidator: { Future.fromTry(syncValidator($0)) },
      onValidated: onValidated)
  }

  func validate() {
    let text = textField.text
    QueueExecution.async(queue) { self.validate(text) }
  }

  private func validate(text: NSString) {
    // never call Future#get here as switcher completes only the latest Future
    switcher(validator(text)).onComplete { result in
      QueueExecution.async(QueueExecution.mainQueue) {
        self.setValidationStyle(result)
        self.onValidated(result)
      }
    }
  }

  private func setValidationStyle(result: Try<T>) {
    if let field = textField {
      switch result {
      case .Success:
        field.layer.borderWidth = validBorderWidth
        field.layer.borderColor = validBorderColor
      case .Failure:
        field.layer.borderWidth = Config.UI.ValidationBorderWidth
        field.layer.borderColor = Config.UI.ValidationBorderColor
      }
      field.layer.cornerRadius = Config.UI.ValidationCornerRadius
    }
  }

  private func change(
    #text: NSString,
    replacement: NSString,
    range: NSRange)
    -> NSString
  {
    let unaffectedStart = text.substringToIndex(range.location)
    let unaffectedEnd = text.substringFromIndex(range.location + range.length)
    return unaffectedStart + replacement + unaffectedEnd
  }
}

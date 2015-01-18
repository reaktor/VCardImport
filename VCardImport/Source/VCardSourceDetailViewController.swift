import UIKit

class VCardSourceDetailViewController: UIViewController {
  @IBOutlet weak var nameField: UITextField!
  @IBOutlet weak var urlField: UITextField!
  @IBOutlet weak var urlValidationLabel: UILabel!
  @IBOutlet weak var isValidatingURLIndicator: UIActivityIndicatorView!
  @IBOutlet weak var isEnabledLabel: UILabel!
  @IBOutlet weak var isEnabledSwitch: UISwitch!

  private let source: VCardSource
  private let isNewSource: Bool
  private let urlConnection: URLConnection
  private let doneCallback: VCardSource -> Void

  private var shouldCallDoneCallbackOnViewDisappear: Bool
  private var nameFieldValidator: TextFieldValidator<String>!
  private var urlFieldValidator: TextFieldValidator<NSURL>!

  private var lastValidName: String?
  private var lastValidURL: NSURL?

  private var isValidCurrentName = false
  private var isValidCurrentURL = false

  // MARK: Controller Life Cycle

  init(
    source: VCardSource,
    isNewSource: Bool,
    urlConnection: URLConnection,
    doneCallback: VCardSource -> Void)
  {
    self.source = source
    self.isNewSource = isNewSource
    self.urlConnection = urlConnection
    self.doneCallback = doneCallback

    shouldCallDoneCallbackOnViewDisappear = !isNewSource

    super.init(nibName: "VCardSourceDetailViewController", bundle: nil)

    if isNewSource {
      navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Cancel, target: self, action: "cancel:")
      navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Done, target: self, action: "done:")
    }
  }

  required init(coder decoder: NSCoder) {
    fatalError("not implemented")
  }

  // MARK: View Life Cycle

  override func viewWillAppear(animated: Bool) {
    super.viewWillDisappear(animated)

    nameFieldValidator = TextFieldValidator(
      textField: nameField,
      syncValidator: { [weak self] text in
        self?.isValidCurrentName = false
        return !text.isEmpty ? .Success(text) : .Failure("empty")
      },
      onValidated: { [weak self] result in
        if let s = self {
          if result.isSuccess {
            s.lastValidName = result.value!
            s.isValidCurrentName = true
          }
          s.refreshDoneButtonState()
        }
      })

    urlFieldValidator = TextFieldValidator(
      textField: urlField,
      asyncValidator: { [weak self] url in
        if let s = self {
          s.isValidCurrentURL = false
          s.beginURLValidationProgress()
          return s.checkIsReachableURL(url)
        } else {
          return Future.failed("view disappeared")
        }
      },
      onValidated: { [weak self] result in
        if let s = self {
          if result.isSuccess {
            s.lastValidURL = result.value!
            s.isValidCurrentURL = true
          }
          s.endURLValidationProgress(result)
          s.refreshDoneButtonState()
        }
      })

    nameField.text = source.name
    urlField.text = source.connection.url.absoluteString
    isEnabledSwitch.on = source.isEnabled
    urlValidationLabel.alpha = 0
    isValidatingURLIndicator.hidesWhenStopped = true

    if isNewSource {
      isEnabledLabel.hidden = true
      isEnabledSwitch.hidden = true
      refreshDoneButtonState()
    } else {
      nameFieldValidator.validate()
      urlFieldValidator.validate()
    }
  }

  override func viewWillDisappear(animated: Bool) {
    super.viewWillDisappear(animated)

    if shouldCallDoneCallbackOnViewDisappear {
      let newName = lastValidName ?? source.name
      let newURL = lastValidURL ?? source.connection.url

      let newSource = source.with(
        name: newName,
        connection: VCardSource.Connection(url: newURL),
        isEnabled: isEnabledSwitch.on
      )

      doneCallback(newSource)
    }
  }

  // MARK: Actions

  func cancel(sender: AnyObject) {
    presentingViewController?.dismissViewControllerAnimated(true, completion: nil)
  }

  func done(sender: AnyObject) {
    shouldCallDoneCallbackOnViewDisappear = true
    presentingViewController?.dismissViewControllerAnimated(true, completion: nil)
  }

  // MARK: Helpers

  private func refreshDoneButtonState() {
    if let button = navigationItem.rightBarButtonItem {
      button.enabled = isValidCurrentName && isValidCurrentURL
    }
  }

  private func beginURLValidationProgress() {
    urlValidationLabel.text = "Validating URL…"

    UIView.animateWithDuration(
      0.5,
      delay: 0,
      options: .CurveEaseIn,
      animations: {
        self.urlValidationLabel.alpha = 1
      },
      completion: nil)

    isValidatingURLIndicator.startAnimating()
  }

  private func endURLValidationProgress(result: Try<NSURL>) {
    switch result {
    case .Success:
      urlValidationLabel.text = "URL is valid"
      UIView.animateWithDuration(
        0.5,
        delay: 0,
        options: .CurveEaseOut,
        animations: {
          self.urlValidationLabel.alpha = 0
        },
        completion: nil)
    case .Failure(let desc):
      urlValidationLabel.text = desc
    }

    isValidatingURLIndicator.stopAnimating()
  }

  private func checkIsReachableURL(urlString: String) -> Future<NSURL> {
    if let url = NSURL(string: urlString) {
      if url.isValidHTTPURL {
        return self.urlConnection
          .head(url, headers: Config.Net.VCardHTTPHeaders)
          .map { _ in url }
      }
    }
    return Future.failed("Invalid URL")
  }
}

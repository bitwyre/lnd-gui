//
//  ReceiveViewController.swift
//  lnd-gui
//
//  Created by Alex Bosworth on 3/12/17.
//  Copyright © 2017 Adylitica. All rights reserved.
//

import Cocoa

/** ReceiveViewController is a view controller for creating invoices
 
 FIXME: - disable the clear button when there is nothing to clear
 FIXME: - disable the create invoice button when there is nothing to create
 FIXME: - add copy button
 FIXME: - don't allow entering too much or too little Satoshis
 FIXME: - when received, show received notification
 FIXME: - do not allow values that are higher than possible
 FIXME: - sometimes the regular address doesn't show up
 FIXME: - show feedback when the amount to send is invalid
 */
class ReceiveViewController: NSViewController, ErrorReporting {
  // MARK: - @IBActions
  
  /** Pressed amount options button
   */
  @IBAction func pressedAmountOptionsButton(_ button: NSPopUpButton) {
    guard let currencyTypeMenuItem = button.selectedItem as? CurrencyTypeMenuItem else {
      return reportError(Failure.expectedCurrencyTypeMenuItem)
    }

    currency = currencyTypeMenuItem.currencyType
  }

  /** Pressed clear button triggers clearing the current payment request.
   */
  @IBAction func pressedClearButton(_ button: NSButton) {
    clear()
  }
  
  /** Pressed blockchain item
   */
  @IBAction func pressedInvoiceBlockchainItem(_ item: NSMenuItem) {
    guard let chainAddress = invoice?.chainAddress else { return reportError(Failure.expectedChainAddress) }
    
    invoiceTextField?.stringValue = chainAddress
  }

  /** Pressed lightning item
   */
  @IBAction func pressedInvoiceLightningItem(_ item: NSMenuItem) {
    guard let invoice = invoice?.invoice else { return reportError(Failure.expectedInvoice) }
    
    invoiceTextField?.stringValue = invoice
  }
  
  /** Pressed request button to trigger the creation of a new request
  
    FIXME: - deal with what happens when there is no forex rate
   */
  @IBAction func pressedRequestButton(_ button: NSButton) {
    guard let amountString = amountTextField?.stringValue else { return }

    let numbers = amountString.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()
    
    let amount: Tokens
    let currencyAmount: CurrencyAmount
    
    switch currency {
    case .testBitcoin:
      currencyAmount = CurrencyAmount(fromTestBitcoins: numbers)
      
    case .testUnitedStatesDollars:
      currencyAmount = CurrencyAmount(fromTestUnitedStatesDollars: numbers)
    }
    
    switch currencyAmount {
    case .testBitcoins(let tokens):
      amount = tokens
      
    case .testUnitedStatesDollars(let dollars):
      guard let wallet = wallet else { return print("EXPECTED WALLET") }
      
      let rate = wallet.centsPerCoin ?? Int()
      
      let cents = dollars * Decimal(100)
      
      let tokens = ((!cents.isNaN ? cents / Decimal(rate) : Decimal()) * 100_000_000) as NSDecimalNumber

      let scale: Int16 = 3
      
      let behavior = NSDecimalNumberHandler(roundingMode: .up, scale: scale, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: true)
      
      amount = Tokens(tokens.rounding(accordingToBehavior: behavior).uint64Value)
    }
    
    guard amount > Tokens() else { return }
    
    do { try addInvoice(amount: amount, description: descriptionTextField?.stringValue) } catch { reportError(error) }
  }

  // MARK: - @IBOutlets

  /** amountTextField is the input text field for the invoice amount.
   */
  @IBOutlet weak var amountTextField: NSTextField?
  
  @IBOutlet weak var clearButton: NSButton?
  
  @IBOutlet weak var currencyConversionTextField: NSTextField?
  
  @IBOutlet weak var currencyTextField: NSTextField?
  
  /** Switcher for invoice type
   */
  @IBOutlet weak var invoiceTypeButton: NSPopUpButton?

  /** descriptionTextField is the input text field for the description.
   */
  @IBOutlet weak var descriptionTextField: NSTextField?
  
  /** Invoice date text field
   */
  @IBOutlet weak var paymentInvoiceDate: NSTextField?

  /** Payment received amount
   */
  @IBOutlet weak var paymentReceivedAmount: NSTextField?

  /** Payment received box
   */
  @IBOutlet weak var paymentReceivedBox: NSBox?

  /** Payment received description
   */
  @IBOutlet weak var paymentReceivedDescription: NSTextField?
  
  /** invoiceHeadingTextField is the label showing the invoice header.
   */
  @IBOutlet weak var invoiceHeadingTextField: NSTextField?
  
  /** invoiceTextField is the label showing the full serialized invoice.
   */
  @IBOutlet weak var invoiceTextField: NSTextField?
  
  /** requestButton is the button that triggers the creation of a new payment request
   */
  @IBOutlet weak var requestButton: NSButton?
  
  /** Select lightning invoice item
   */
  @IBOutlet weak var selectLightningItem: NSMenuItem?
  
  // MARK: - Properties
  
  var creatingInvoice = false { didSet { updatedCreatingInvoice() } }
  
  var currency: CurrencyType = .testBitcoin { didSet { do { try updatedSelectedCurrency() } catch { reportError(error) } } }
  
  /** invoice is the created invoice to receive funds to.
   */
  var invoice: LightningInvoice? { didSet { updatedInvoice() } }

  /** Paid invoice
   */
  var paidInvoice: Transaction? { didSet { updatedPaidInvoice() } }
  
  /** Report error
   */
  lazy var reportError: (Error) -> () = { _ in }
  
  /** Show an invoice
   */
  lazy var showInvoice: (LightningInvoice) -> () = { _ in }
  
  /** Wallet
   */
  var wallet: Wallet?
}

// MARK: - Failures
extension ReceiveViewController {
  enum Failure: Error {
    case expectedChainAddress
    case expectedCurrencyTypeMenuItem
    case expectedCurrentEvent
    case expectedInvoice
    case expectedInvoiceCreationDate
  }
}

// MARK: - Networking
extension ReceiveViewController {
  /** Updated creating invoice state
   */
  func updatedCreatingInvoice() {
    switch creatingInvoice {
    case false:
      amountTextField?.isEditable = true
      clearButton?.isEnabled = true
      clearButton?.state = NSOnState
      descriptionTextField?.isEditable = true
      requestButton?.isEnabled = true
      requestButton?.state = NSOnState
      requestButton?.title = NSLocalizedString("Request Payment", comment: "Create new invoice button")
      
    case true:
      amountTextField?.isEditable = false
      clearButton?.isEnabled = false
      clearButton?.state = NSOffState
      descriptionTextField?.isEditable = false
      requestButton?.isEnabled = false
      requestButton?.state = NSOffState
      requestButton?.title = NSLocalizedString("Creating Invoice", comment: "Created invoice, waiting for invoice")
    }
  }
  
  /** Send a request to make an invoice.
   */
  func addInvoice(amount: Tokens, description: String? = nil) throws {
    // Use defer to avoid setting create invoice to true when the addInvoice method throws an Error
    defer { creatingInvoice = true }

    try Daemon.addInvoice(amount: amount, description: description) { [weak self] result in
      self?.clear()
      
      self?.creatingInvoice = false
      
      switch result {
      case .addedInvoice(let invoice):
        self?.showInvoice(invoice)
        
      case .error(let error):
        self?.reportError(error)
      }
    }
  }
}

// MARK: - NSTextViewDelegate
extension ReceiveViewController: NSTextViewDelegate {
  override func controlTextDidChange(_ obj: Notification) {
    do { try updatedSelectedCurrency() } catch { reportError(error) }
  }
}

// MARK: - NSViewController
extension ReceiveViewController {
  /** clear eliminates the input and previous created invoice from the view.
   */
  fileprivate func clear() {
    let addedInvoiceViews: [NSView?] = [invoiceHeadingTextField, invoiceTextField, invoiceTypeButton]
    let inputTextFields = [amountTextField, descriptionTextField]
    
    inputTextFields.forEach { $0?.stringValue = String() }
    addedInvoiceViews.forEach { $0?.isHidden = true }
    
    invoiceTypeButton?.select(selectLightningItem)
    
    paidInvoice = nil

    do { try updatedSelectedCurrency() } catch { reportError(error) }
  }
  
  /** Updated paid invoice
   */
  fileprivate func updatedPaidInvoice() {
    guard let paidInvoice = paidInvoice else { paymentReceivedBox?.isHidden = true; return }
    
    guard let invoiceDate = paidInvoice.createdAt else { return reportError(Failure.expectedInvoiceCreationDate) }
    
    switch paidInvoice {
    case .blockchain(_):
      break

    case .lightning(let lightningTransaction):
      switch lightningTransaction {
      case .invoice(let paidInvoice):
        paymentInvoiceDate?.stringValue = invoiceDate.formatted(dateStyle: .short, timeStyle: .short)
        paymentReceivedAmount?.stringValue = paidInvoice.tokens.formatted(with: .testBitcoin)
        paymentReceivedBox?.isHidden = false
        paymentReceivedDescription?.stringValue = (paidInvoice.description ?? String()) as String
        
      case .payment(_):
        break
      }
    }
  }
  
  fileprivate func updatedSelectedCurrency() throws {
    let amountPlaceholder: String
    
    switch currency {
    case .testBitcoin:
      amountPlaceholder = "0.00000000"
      
    case .testUnitedStatesDollars:
      amountPlaceholder = "$0.00"
    }
    
    amountTextField?.placeholderString = amountPlaceholder

    let converted = try currencyConverted(from: amountTextField?.stringValue)
    
    currencyConversionTextField?.stringValue = converted
  }
  
  func currencyConverted(from amountString: String?) throws -> String {
    guard let amountString = amountString else { return String() }
    
    let numbers = amountString.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()
    
    guard let centsPerCoin = wallet?.centsPerCoin else { return String() }
    
    switch currency {
    case .testBitcoin:
      let bitcoins = CurrencyAmount(fromTestBitcoins: numbers)
      
      return try bitcoins.converted(to: .testUnitedStatesDollars, rate: centsPerCoin)
      
    case .testUnitedStatesDollars:
      let dollars = CurrencyAmount(fromTestUnitedStatesDollars: numbers)
      
      let formattedCoins = try dollars.converted(to: .testBitcoin, rate: centsPerCoin)
      
      return "(\(formattedCoins))"
    }
  }
  
  /** Updated the payment request
   */
  fileprivate func updatedInvoice() {
    invoiceTextField?.stringValue = (invoice?.invoice ?? String()) as String
    
    let hasNoInvoice = invoice?.invoice == nil
    
    invoiceTypeButton?.isHidden = hasNoInvoice
    
    guard let _ = invoice else { return }
    
    invoiceHeadingTextField?.isHidden = false
    invoiceTextField?.isHidden = false
    requestButton?.isEnabled = true
    requestButton?.state = NSOnState
    requestButton?.title = NSLocalizedString("Request Payment", comment: "Button to add a new payment request")
  }
  
  /** viewDidLoad triggers to initialize the view.
   */
  override func viewDidLoad() {
    super.viewDidLoad()
    
    clear()
  }
  
  /** View is going to disappear
   */
  override func viewWillDisappear() {
    super.viewWillDisappear()
    
    paidInvoice = nil
  }
}

// MARK: - WalletListener
extension ReceiveViewController: WalletListener {
  /** Wallet was updated
   */
  func walletUpdated() {
    guard let invoice = invoice, let currentInvoice = wallet?.invoice(invoice), currentInvoice.isConfirmed else { return }

    paidInvoice = Transaction.lightning(LightningTransaction.invoice(currentInvoice))
    
    clear()
  }
}

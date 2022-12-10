//
//  ChatViewController.swift
//  NearTalk
//
//  Created by dong eun shin on 2022/11/23.
//

import RxRelay
import RxSwift
import UIKit

final class ChatViewController: UIViewController {
    // MARK: - UI properties
    private lazy var compositionalLayout: UICollectionViewCompositionalLayout = self.createLayout()
    
    private lazy var collectionView: UICollectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: compositionalLayout
    ).then {
        $0.backgroundColor = .primaryBackground
        $0.showsVerticalScrollIndicator = false
        $0.register(ChatCollectionViewCell.self, forCellWithReuseIdentifier: ChatCollectionViewCell.identifier)
        $0.delegate = self
    }
    
    private lazy var chatInputAccessoryView: ChatInputAccessoryView = ChatInputAccessoryView().then {
        $0.backgroundColor = .primaryBackground
    }
    
    // MARK: - Proporties
    
    private let viewModel: ChatViewModel
    private var messageItems: [MessageItem]
    
    private let disposeBag: DisposeBag = DisposeBag()
    private lazy var dataSource: DataSource = makeDataSource()

    private var isReadyToFetchPreviousMessages: Bool = false
    private let isLatestMessageChanged: BehaviorRelay<Bool> = .init(value: false)
        
    // MARK: - Lifecycles
    
    init(viewModel: ChatViewModel) {
        self.messageItems = []
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .primaryBackground
        addSubviews()
        bind()
        
        // 키보드
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardHandler(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardHandler(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        // 제스처
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard(_:)))
        view.addGestureRecognizer(tapGesture)
    }
    
    private func addSubviews() {
        [collectionView, chatInputAccessoryView].forEach {
            self.view.addSubview($0)
        }
        
        chatInputAccessoryView.snp.makeConstraints { make in
            make.leading.trailing.equalTo(self.view.safeAreaLayoutGuide)
            make.height.equalTo(55)
            make.bottom.equalTo(self.view.safeAreaLayoutGuide)
        }
        
        collectionView.snp.makeConstraints { make in
            make.leading.trailing.equalTo(self.view.safeAreaLayoutGuide)
            make.top.equalTo(self.view.safeAreaLayoutGuide)
            make.bottom.equalTo(chatInputAccessoryView.snp.top)
        }
    }
    
    private func createLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .estimated(40.0))
        
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .estimated(40))
        
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                         subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 8.0

        let layout = UICollectionViewCompositionalLayout(section: section)
        
        return layout
    }
    
    private func scrollToBottom() {
        guard self.isLatestMessageChanged.value else {
            return
        }
        let indexPath = IndexPath(item: messageItems.count - 1, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: true)
    }
        
    private func bind() {
        self.chatInputAccessoryView.messageInputTextField.rx.text.orEmpty
            .map { !$0.isEmpty }
            .bind(to: chatInputAccessoryView.sendButton.rx.isEnabled)
            .disposed(by: disposeBag)
        
        self.chatInputAccessoryView.sendButton.rx.tap
            .withLatestFrom(chatInputAccessoryView.messageInputTextField.rx.text.orEmpty)
            .filter { !$0.isEmpty }
            .bind { [weak self] message in
                self?.viewModel.sendMessage(message)
                self?.chatInputAccessoryView.messageInputTextField.text = nil
                self?.chatInputAccessoryView.sendButton.isEnabled = false
            }
            .disposed(by: disposeBag)
        
        self.viewModel.chatMessages
            .asDriver(onErrorJustReturn: [])
            .drive(onNext: { [weak self] messages in
                guard let self,
                      let myID = self.viewModel.myID else {
                    return
                }

                self.isLatestMessageChanged.accept(messages.last?.uuid != self.messageItems.last?.id)
                
                var messageItems: [MessageItem] = []
                messages.forEach { message in
                    let userProfile: UserProfile? = self.viewModel.getUserProfile(userID: message.senderID ?? "")
                    let messageItem: MessageItem = .init(
                        chatMessage: message,
                        myID: myID,
                        userProfile: userProfile
                    )
                    messageItems.append(messageItem)
                }
                
                self.messageItems = messageItems
                let snapshot = self.appendSnapshot(items: self.messageItems)
                self.dataSource.apply(snapshot, animatingDifferences: self.isReadyToFetchPreviousMessages) {
                    self.scrollToBottom()
                }
            })
            .disposed(by: self.disposeBag)
        
        self.viewModel.chatRoom
            .bind { [weak self] chatRoom in
                guard let self,
                      let chatRoom else {
                    return
                }
                self.navigationItem.title = "\(chatRoom.roomName ?? "Unknown") (\(chatRoom.userList?.count ?? 0))"
            }
            .disposed(by: self.disposeBag)
    }
}

// MARK: - UICollectionViewDelegate
extension ChatViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        print("🚧 ", #function, indexPath.row)
        
        if indexPath.row > 29,
           !self.isReadyToFetchPreviousMessages {
            self.isReadyToFetchPreviousMessages.toggle()
        }
        
        if indexPath.row < 10,
           isReadyToFetchPreviousMessages {
            self.viewModel.fetchMessages(before: self.viewModel.chatMessages.value[0], isInitialMessage: false)
        }
    }
}

// MARK: - UICollectionViewDiffableDataSource
private extension ChatViewController {
    typealias DataSource = UICollectionViewDiffableDataSource<Section, MessageItem>
    typealias Snapshot = NSDiffableDataSourceSnapshot<Section, MessageItem>
    
    enum Section {
        case main
    }
    
    func makeDataSource() -> DataSource {
        let datasource = DataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            guard let self,
                  let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ChatCollectionViewCell.identifier,
                    for: indexPath) as? ChatCollectionViewCell
            else {
                return UICollectionViewCell()
            }
            cell.configure(messageItem: item) {
                var snapshot = self.dataSource.snapshot()
                snapshot.reloadItems([item])
            }
            return cell
        }
        return datasource
    }
    
    func appendSnapshot(items: [MessageItem]) -> NSDiffableDataSourceSnapshot<Section, MessageItem> {
        var snapshot = Snapshot()
        snapshot.appendSections([.main])
        snapshot.appendItems(messageItems.sorted { $0.createdAt < $1.createdAt })
        return snapshot
    }
}

// MARK: - Keyboard
private extension ChatViewController {
    @objc
    func keyboardHandler(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let keyboardAnimationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
              let keyboardDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let keyboardCurve = UIView.AnimationCurve(rawValue: keyboardAnimationCurve)
        else {
            return
        }
        
        let keyboardSize = keyboardFrame.cgRectValue
        let keyboardHeight = keyboardSize.height
        
        let safeAreaExists = (self.view?.window?.safeAreaInsets.bottom != 0)
        let bottomConstant: CGFloat = 20
        let newConstant = keyboardHeight + (safeAreaExists ? 0 : bottomConstant)
        
        self.chatInputAccessoryView.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(newConstant)
        }
        
        self.collectionView.snp.makeConstraints { make in
            make.bottom.equalTo(chatInputAccessoryView.snp.top)
        }
        
        let animator = UIViewPropertyAnimator(duration: keyboardDuration, curve: keyboardCurve) { [weak self] in
            self?.view.layoutIfNeeded()
        }
        
        animator.startAnimation()
        self.scrollToBottom()
    }
    
    @objc
    func hideKeyboard(_ sender: Any) {
        view.endEditing(true)
        self.chatInputAccessoryView.snp.remakeConstraints { make in
            make.width.equalTo(self.view.frame.width)
            make.height.equalTo(50)
            make.bottom.equalTo(self.view.safeAreaLayoutGuide)
        }

        self.collectionView.snp.remakeConstraints { make in
            make.top.equalTo(self.view.safeAreaLayoutGuide)
            make.leading.trailing.equalTo(self.view.safeAreaLayoutGuide)
            make.bottom.equalTo(chatInputAccessoryView.snp.top)
        }
    }
}

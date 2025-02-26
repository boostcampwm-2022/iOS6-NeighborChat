//
//  ChatRoomListViewModel.swift
//  NearTalk
//
//  Created by yw22 on 2022/11/11.
//
 
import Foundation
import RxRelay
import RxSwift

struct ChatRoomListViewModelActions {
    let showChatRoom: (String) -> Void
    let showCreateChatRoom: () -> Void
    let showDMChatRoomList: () -> Void
    let showGroupChatRoomList: () -> Void
    let showAlert: () -> Void
}

protocol ChatRoomListViewModelInput {
    func getUserChatRoomTicket(roomID: String) -> Single<UserChatRoomTicket>
    func getUserProfile(userID: String) -> Single<UserProfile>
    func getMyProfile() -> UserProfile?
    func didDMChatRoomList()
    func didGroupChatRoomList()
    func didCreateChatRoom()
    func didSelectItem(at roomID: String, inArea: Bool)
    func viewWillAppear()
}

protocol ChatRoomListViewModelOutput {
    var groupChatRoomData: BehaviorRelay<[GroupChatRoomListData]> { get }
    var dmChatRoomData: BehaviorRelay<[DMChatRoomListData]> { get }
    var userChatRoomTicket: UserChatRoomTicket? { get }
}

protocol ChatRoomListViewModel: ChatRoomListViewModelInput, ChatRoomListViewModelOutput {}

final class DefaultChatRoomListViewModel: ChatRoomListViewModel {
    private let chatRoomListUseCase: FetchChatRoomUseCase
    private let actions: ChatRoomListViewModelActions?
    private let disposeBag: DisposeBag = DisposeBag()

    // MARK: - Output
    var groupChatRoomData: BehaviorRelay<[GroupChatRoomListData]> = BehaviorRelay<[GroupChatRoomListData]>(value: [])
    var dmChatRoomData: BehaviorRelay<[DMChatRoomListData]> = BehaviorRelay<[DMChatRoomListData]>(value: [])
    var userChatRoomTicket: UserChatRoomTicket?
    var verifyDistance: BehaviorRelay<Bool> = BehaviorRelay<Bool>(value: true)
    
    init(useCase: FetchChatRoomUseCase, actions: ChatRoomListViewModelActions? = nil) {
        self.chatRoomListUseCase = useCase
        self.actions = actions
        
        self.chatRoomListUseCase.createObservableGroupChatList()
            .bind(to: groupChatRoomData)
            .disposed(by: self.disposeBag)
        
        self.chatRoomListUseCase.createObservableDMChatList()
            .bind(to: dmChatRoomData)
            .disposed(by: self.disposeBag)
        
    }
    
    func getUserChatRoomTicket(roomID: String) -> Single<UserChatRoomTicket> {
        self.chatRoomListUseCase.getUserChatRoomTicket(roomID: roomID)
    }
    
    func getMyProfile() -> UserProfile? {
        self.chatRoomListUseCase.getMyProfile()
    }
    
    func getUserProfile(userID: String) -> Single<UserProfile> {
        return self.chatRoomListUseCase.getUserProfile(userID: userID)
    }
}

// MARK: - Input
extension DefaultChatRoomListViewModel {
    func viewWillAppear() {
        self.chatRoomListUseCase.newGetChatRoomUUIDList()
    }
    
    func didDMChatRoomList() {
        actions?.showDMChatRoomList()
    }
    
    func didGroupChatRoomList() {
        actions?.showGroupChatRoomList()
    }
    
    func didSelectItem(at roomID: String, inArea: Bool) {
        if inArea {
            actions?.showChatRoom(roomID)
        } else {
            actions?.showAlert()
        }
    }
    
    // 체팅방 생성 클릭시 이동
    func didCreateChatRoom() {
        actions?.showCreateChatRoom()
    }
}

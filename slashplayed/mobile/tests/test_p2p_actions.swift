import Foundation
@main struct P2PTests {
    static func main() {
        precondition(SPP2PAction.sample([0,0], uniform: 0.1) == 0)
        precondition(SPP2PAction.sample([0,0], uniform: 0.9) == 1)
        precondition(SPP2PAction.sample([-1000,0], uniform: 0.3) == 1)
        precondition(SPP2PAction.sample([Double.nan,0], uniform: 0.3) == nil)
        precondition(SPP2PAction.sample([0], uniform: 1) == nil)
        precondition(SPP2PAction.movement([0,0,0,0,1,2,15,8]) == "WAIT")
        precondition(SPP2PAction.movement([1,2,11,0]) == "FORWARD")
        precondition(SPP2PAction.movement([10,0,0,0]) == "STRAFE_LEFT")
        precondition(SPP2PAction.movement([8,0,0,0]) == "STRAFE_RIGHT")
        precondition(SPP2PAction.executedIDs["FORWARD"] == 11)
        precondition(SPP2PAction.movement([15,0,0,0]) == "FORWARD")
        print("Pixel2Play action adapter tests passed")
    }
}

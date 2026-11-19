enum SPMobileZone { SPMobileDefault, SPMobileMove, SPMobileLook, SPMobileInterface };

static enum SPMobileZone sp_mobile_zone(double x, double y, int interface) {
    if (x < 0 || x > 1 || y < 0 || y > 1) return SPMobileDefault;
    if (interface) return SPMobileInterface;
    if (x < 0.43 && y >= 0.50) return SPMobileMove;
    if (x >= 0.50 && y >= 0.18 && y <= 0.88) return SPMobileLook;
    return SPMobileDefault;
}

// Prioritize the floating joystick when dragging in the lower-left phone zone.
static inline enum SPMobileZone sp_mobile_phone_zone(double x, double y, int interface) {
    if (sp_mobile_zone(x, y, 0) == SPMobileMove) return SPMobileMove;
    return sp_mobile_zone(x, y, interface);
}

// Distances are UIKit points; elapsed is UITouch's monotonic seconds.
// A gesture that moved (even if it returned to the origin) is not a click.
enum SPMobileClick { SPMobileNoClick = -1, SPMobileLeftClick = 0, SPMobileRightClick = 1 };
#define SP_MOBILE_DRAG_DISTANCE 7.0
#define SP_MOBILE_RIGHT_PRESS_SECONDS 0.45

static inline enum SPMobileClick sp_mobile_click(double elapsed, double distance, int interrupted) {
    if (interrupted || distance >= SP_MOBILE_DRAG_DISTANCE) return SPMobileNoClick;
    return elapsed >= SP_MOBILE_RIGHT_PRESS_SECONDS ? SPMobileRightClick : SPMobileLeftClick;
}

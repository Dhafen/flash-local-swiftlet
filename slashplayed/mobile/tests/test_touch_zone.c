#include <assert.h>
#include "../touch-zone.h"

int main(void) {
    assert(sp_mobile_zone(0.20, 0.70, 0) == SPMobileMove);
    assert(sp_mobile_zone(0.80, 0.65, 0) == SPMobileLook);
    assert(sp_mobile_zone(0.20, 0.70, 1) == SPMobileInterface);
    assert(sp_mobile_phone_zone(0.20, 0.70, 1) == SPMobileMove);
    assert(sp_mobile_phone_zone(0.80, 0.65, 1) == SPMobileInterface);
    assert(sp_mobile_phone_zone(0.80, 0.65, 0) == SPMobileLook);
    assert(sp_mobile_phone_zone(-0.01, 0.65, 1) == SPMobileDefault);
    assert(sp_mobile_zone(0.80, 0.65, 1) == SPMobileInterface);
    assert(sp_mobile_zone(0.45, 0.65, 0) == SPMobileDefault);
    assert(sp_mobile_zone(-0.01, 0.65, 1) == SPMobileDefault);
    assert(sp_mobile_click(0.1, 0, 0) == SPMobileLeftClick);
    assert(sp_mobile_click(0.449, 1, 0) == SPMobileLeftClick);
    assert(sp_mobile_click(0.45, 2, 0) == SPMobileRightClick);
    assert(sp_mobile_click(2.0, 6.99, 0) == SPMobileRightClick);
    assert(sp_mobile_click(0.1, 7.0, 0) == SPMobileNoClick);
    assert(sp_mobile_click(0.9, 20, 0) == SPMobileNoClick);
    assert(sp_mobile_click(0.9, 0, 1) == SPMobileNoClick);
    assert(sp_mobile_click(0.1, 0, 1) == SPMobileNoClick);
}

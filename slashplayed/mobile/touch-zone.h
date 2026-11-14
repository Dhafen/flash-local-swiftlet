enum SPMobileZone { SPMobileDefault, SPMobileMove, SPMobileLook, SPMobileInterface };

static enum SPMobileZone sp_mobile_zone(double x, double y, int interface) {
    if (x < 0 || x > 1 || y < 0 || y > 1) return SPMobileDefault;
    if (interface) return SPMobileInterface;
    if (x < 0.43 && y >= 0.50) return SPMobileMove;
    if (x >= 0.50 && y >= 0.18 && y <= 0.88) return SPMobileLook;
    return SPMobileDefault;
}

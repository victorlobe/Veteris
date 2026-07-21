@interface LoadingIndicatorView : UIView
+ (LoadingIndicatorView*)attachToView:(UIView *)view;
+ (LoadingIndicatorView*)attachToView:(UIView *)view textKey:(NSString *)textKey;
- (void)constructWithCenter:(CGPoint)center;
- (void)constructWithCenter:(CGPoint)center textKey:(NSString *)textKey;
- (void)destroy;
@end

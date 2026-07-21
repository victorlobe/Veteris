//
//  VeterisResetController.h
//  Veteris
//
//  Created by Victor on 01.07.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VeterisResetController : NSObject <UIAlertViewDelegate>

+ (void)confirmReset:(id)sender forKey:(NSString *)key;

@end

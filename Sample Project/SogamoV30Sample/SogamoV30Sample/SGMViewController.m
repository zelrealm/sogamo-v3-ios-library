//
//  SGMViewController.m
//  SogamoV30Sample
//
//  Created by Chadin Anuwattanaporn on 20/6/14.
//  Copyright (c) 2014 Sogamo. All rights reserved.
//

#import "SGMViewController.h"
#import "Sogamo.h"

@interface SGMViewController ()

@end

@implementation SGMViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    self.eventName.text = @"Important event";
    
    [self.trackButton setTitle:@"Track" forState:UIControlStateNormal];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)trackButtonClick:(id)sender {
    
    Sogamo *sogamo = [Sogamo sharedInstance];
    
    [sogamo track:self.eventName.text];
}

@end

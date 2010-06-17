//
//  ASIAuthenticationDialog.m
//  Part of ASIHTTPRequest -> http://allseeing-i.com/ASIHTTPRequest
//
//  Created by Ben Copsey on 21/08/2009.
//  Copyright 2009 All-Seeing Interactive. All rights reserved.
//

#import "ASIAuthenticationDialog.h"
#import "ASIHTTPRequest.h"

ASIAuthenticationDialog *sharedDialog = nil;
NSLock *dialogLock = nil;
BOOL isDismissing = NO;

static const NSUInteger kUsernameRow = 0;
static const NSUInteger kUsernameSection = 0;
static const NSUInteger kPasswordRow = 1;
static const NSUInteger kPasswordSection = 0;
static const NSUInteger kDomainRow = 0;
static const NSUInteger kDomainSection = 1;


@implementation ASIAutorotatingViewController

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
#if __IPHONE_3_2 && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_2
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
		return YES;
	}
#endif
	return (toInterfaceOrientation == UIInterfaceOrientationPortrait);
}

@end


@interface ASIAuthenticationDialog ()
- (void)show;
@property (retain) UITableView *tableView;
@property (retain) UIBarButtonItem *loginButton;
@end

@implementation ASIAuthenticationDialog

#pragma mark init / dealloc

+ (void)initialize
{
	if (self == [ASIAuthenticationDialog class]) {
		dialogLock = [[NSLock alloc] init];
	}
}

+ (void)presentProxyAuthenticationDialogForRequest:(ASIHTTPRequest *)request
{
	[dialogLock lock];
	if (!sharedDialog) {
		sharedDialog = [[self alloc] init];
	}
	[sharedDialog setRequest:request];
	[sharedDialog setType:ASIProxyAuthenticationType];
	[sharedDialog show];
	[dialogLock unlock];
}

+ (void)presentAuthenticationDialogForRequest:(ASIHTTPRequest *)request
{
	[dialogLock lock];
	if (!sharedDialog) {
		sharedDialog = [[self alloc] init];
	}
	[sharedDialog setRequest:request];
	[sharedDialog show];
	[dialogLock unlock];
}

- (id)init
{
	if ((self = [self initWithNibName:nil bundle:nil])) {
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(keyboardWillShow:)
		 name:UIKeyboardWillShowNotification
		 object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter]
	 removeObserver:self name:UIKeyboardWillShowNotification object:nil];

	[request release];
	[tableView release];
	[loginButton release];
	[presentingController.view removeFromSuperview];
	[presentingController release];
	[super dealloc];
}

#pragma mark keyboard notifications

- (void)keyboardWillShow:(NSNotification *)notification
{
#if __IPHONE_3_2 && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_2
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
#endif
		NSValue *keyboardBoundsValue = [[notification userInfo] objectForKey:UIKeyboardBoundsUserInfoKey];
		CGRect keyboardBounds;
		[keyboardBoundsValue getValue:&keyboardBounds];
		UIEdgeInsets e = UIEdgeInsetsMake(0, 0, keyboardBounds.size.height, 0);
		[[self tableView] setScrollIndicatorInsets:e];
		[[self tableView] setContentInset:e];
#if __IPHONE_3_2 && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_2
	}
#endif
}

#pragma mark utilities

- (UIViewController *)presentingController
{
	if (!presentingController) {
		presentingController = [[ASIAutorotatingViewController alloc] initWithNibName:nil bundle:nil];

		// Attach to the window, but don't interfere.
		UIWindow *window = [[[UIApplication sharedApplication] windows] objectAtIndex:0];
		[window addSubview:presentingController.view];
		[[presentingController view] setFrame:CGRectZero];
		[[presentingController view] setUserInteractionEnabled:NO];
	}

	return presentingController;
}

- (UITextField *)textFieldInRow:(NSUInteger)row section:(NSUInteger)section
{
	return [[[[[self tableView] cellForRowAtIndexPath:
			   [NSIndexPath indexPathForRow:row inSection:section]]
			  contentView] subviews] objectAtIndex:0];
}

- (UITextField *)usernameField
{
	return [self textFieldInRow:kUsernameRow section:kUsernameSection];
}

- (UITextField *)passwordField
{
	return [self textFieldInRow:kPasswordRow section:kPasswordSection];
}

- (UITextField *)domainField
{
	return [self textFieldInRow:kDomainRow section:kDomainSection];
}

#pragma mark show / dismiss

+ (void)dismiss
{
	[dialogLock lock];
	[[sharedDialog parentViewController] dismissModalViewControllerAnimated:YES];
	[sharedDialog release];
	sharedDialog = nil;
	[dialogLock unlock];
}

- (void)dismiss
{
	if (self == sharedDialog) {
		[[self class] dismiss];
	} else {
		[[self parentViewController] dismissModalViewControllerAnimated:YES];
	}
}

- (void)show
{
	// Remove all subviews
	UIView *v;
	while ((v = [[[self view] subviews] lastObject])) {
		[v removeFromSuperview];
	}

	// Setup toolbar
	UINavigationBar *bar = [[[UINavigationBar alloc] init] autorelease];
	[bar setAutoresizingMask:UIViewAutoresizingFlexibleWidth];

	UINavigationItem *navItem = [[[UINavigationItem alloc] init] autorelease];
	bar.items = [NSArray arrayWithObject:navItem];

	[[self view] addSubview:bar];

	// Setup the title
	if ([self type] == ASIProxyAuthenticationType) {
		[navItem setPrompt:@"Login to this secure proxy server."];
	} else {
		[navItem setPrompt:@"Login to this secure server."];
	}

	// Setup toolbar buttons
	if ([self type] == ASIProxyAuthenticationType) {
		[navItem setTitle:[[self request] proxyHost]];
	} else {
		[navItem setTitle:[[[self request] url] host]];
	}

	[self setLoginButton:[[UIBarButtonItem alloc] initWithTitle:@"Login" style:UIBarButtonItemStyleDone target:self action:@selector(loginWithCredentialsFromDialog:)]];
	[navItem setLeftBarButtonItem:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelAuthenticationFromDialog:)] autorelease]];
	[navItem setRightBarButtonItem:loginButton];
	loginButton.enabled = NO;

	// We show the login form in a table view, similar to Safari's authentication dialog
	[bar sizeToFit];
	CGRect f = [[self view] bounds];
	f.origin.y = [bar frame].size.height;
	f.size.height -= f.origin.y;

	[self setTableView:[[[UITableView alloc] initWithFrame:f style:UITableViewStyleGrouped] autorelease]];
	[[self tableView] setDelegate:self];
	[[self tableView] setDataSource:self];
	[[self tableView] setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
	[[self view] addSubview:[self tableView]];

	// Force reload the table content, and focus the first field to show the keyboard
	[[self tableView] reloadData];
	[[[[[self tableView] cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]].contentView subviews] objectAtIndex:0] becomeFirstResponder];

#if __IPHONE_3_2 && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_2
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
		[self setModalPresentationStyle:UIModalPresentationFormSheet];
	}
#endif

	[[self presentingController] presentModalViewController:self animated:YES];
}

#pragma mark button callbacks

- (void)cancelAuthenticationFromDialog:(id)sender
{
	[[self request] cancelAuthentication];
	[self dismiss];
}

- (void)loginWithCredentialsFromDialog:(id)sender
{
	NSString *username = [[self usernameField] text];
	NSString *password = [[self passwordField] text];

	if ([self type] == ASIProxyAuthenticationType) {
		[[self request] setProxyUsername:username];
		[[self request] setProxyPassword:password];
	} else {
		[[self request] setUsername:username];
		[[self request] setPassword:password];
	}

	// Handle NTLM domains
	NSString *scheme = ([self type] == ASIStandardAuthenticationType) ? [[self request] authenticationScheme] : [[self request] proxyAuthenticationScheme];
	if ([scheme isEqualToString:(NSString *)kCFHTTPAuthenticationSchemeNTLM]) {
		NSString *domain = [[self domainField] text];
		if ([self type] == ASIProxyAuthenticationType) {
			[[self request] setProxyDomain:domain];
		} else {
			[[self request] setDomain:domain];
		}
	}

	[[self request] retryUsingSuppliedCredentials];
}

#pragma mark table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)aTableView
{
	NSString *scheme = ([self type] == ASIStandardAuthenticationType) ? [[self request] authenticationScheme] : [[self request] proxyAuthenticationScheme];
	if ([scheme isEqualToString:(NSString *)kCFHTTPAuthenticationSchemeNTLM]) {
		return 2;
	}
	return 1;
}

- (CGFloat)tableView:(UITableView *)aTableView heightForFooterInSection:(NSInteger)section
{
	if (section == [self numberOfSectionsInTableView:aTableView]-1) {
		return 30;
	}
	return 0;
}

- (CGFloat)tableView:(UITableView *)aTableView heightForHeaderInSection:(NSInteger)section
{
	if (section == 0) {
#if __IPHONE_3_2 && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_2
		if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
			return 54;
		}
#endif
		return 30;
	}
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if (section == 0) {
		return [[self request] authenticationRealm];
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_3_0
	UITableViewCell *cell = [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:nil] autorelease];
#else
	UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
#endif

	[cell setSelectionStyle:UITableViewCellSelectionStyleNone];

	CGRect f = CGRectInset(cell.bounds, 10, 10);
	UITextField *textField = [[[UITextField alloc] initWithFrame:f] autorelease];
	[textField setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
	[textField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
	[textField setAutocorrectionType:UITextAutocorrectionTypeNo];
	[textField setDelegate:self];

	NSUInteger s = [indexPath section];
	NSUInteger r = [indexPath row];

	if (s == kUsernameSection && r == kUsernameRow) {
		[textField setPlaceholder:@"User"];
	} else if (s == kPasswordSection && r == kPasswordRow) {
		[textField setPlaceholder:@"Password"];
		[textField setSecureTextEntry:YES];
	} else if (s == kDomainSection && r == kDomainRow) {
		[textField setPlaceholder:@"Domain"];
	}
	[cell.contentView addSubview:textField];

	return cell;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if (section == 0) {
		return 2;
	} else {
		return 1;
	}
}

- (NSString *)tableView:(UITableView *)aTableView titleForFooterInSection:(NSInteger)section
{
	if (section == [self numberOfSectionsInTableView:aTableView]-1) {
		// If we're using Basic authentication and the connection is not using SSL, we'll show the plain text message
		if ([[[self request] authenticationScheme] isEqualToString:(NSString *)kCFHTTPAuthenticationSchemeBasic] && ![[[[self request] url] scheme] isEqualToString:@"https"]) {
			return @"Password will be sent in the clear.";
		// We are using Digest, NTLM, or any scheme over SSL
		} else {
			return @"Password will be sent securely.";
		}
	}
	return nil;
}

#pragma mark text field delegates

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	NSString *newString = [[textField text] stringByReplacingCharactersInRange:range withString:string];
	NSArray *fields = [NSArray arrayWithObjects:
					   [self usernameField],
					   [self passwordField],
					   [self domainField], // ends the array early if not set
					   nil];
	BOOL allFilled = YES;

	for (UITextField *field in fields) {
		NSString *text = nil;
		if (field == textField) {
			text = newString;
		} else {
			text = [field text];
		}

		if ([text length] == 0) {
			allFilled = NO;
			break;
		}
	}

	loginButton.enabled = allFilled;
	return YES;
}

#pragma mark -

@synthesize request;
@synthesize type;
@synthesize tableView;
@synthesize loginButton;
@end

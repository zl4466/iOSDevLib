/*
 *	RFService.m
 *	RESTframework
 *
 *	Created by Ivan Vasić on 9/4/11.
 *	Copyright 2011 Ivan Vasic https://github.com/ivasic/RESTframework.
 *
 *	RESTframework is free software: you can redistribute it and/or modify
 *	it under the terms of the GNU Lesser General Public License as published by
 *	the Free Software Foundation, either version 3 of the License, or
 *	(at your option) any later version.
 *
 *	RESTframework is distributed in the hope that it will be useful,
 *	but WITHOUT ANY WARRANTY; without even the implied warranty of
 *	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *	GNU Lesser General Public License for more details.
 *	
 *	You should have received a copy of the GNU Lesser General Public License
 *	along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#import "RFService.h"
#import "RFconf.h"
#import "RFRequest.h"
#import "RFResponse.h"

@interface RFService ()
@property (nonatomic, strong) RFRequest* currentRequest;
@property (weak, readonly) NSMutableArray* requestsQueue;
@property (strong) id<RFServiceDelegate> asyncDelegate;
@property (copy) RFRequestCompletion asyncCompletionBlock;
@property (copy) void(^dataReceivedlock)(NSUInteger totalBytesReceived);
@property (copy) void(^dataSentBlock)(NSUInteger totalBytesSent, NSUInteger totalBytesExpected);
@end

@interface RFService (privates)
-(void) continueExecFromQueue;
@end

@implementation RFService
@synthesize delegate, currentRequest, requestsQueue, asyncDelegate, asyncCompletionBlock, dataReceivedlock, dataSentBlock;

#pragma mark - Props

-(NSMutableArray*) requestsQueue
{
	if (!requestsQueue) {
		requestsQueue = [NSMutableArray array];
	}
	
	return requestsQueue;
}

#pragma mark - Initialization

-(void) dealloc {
	[self cancelRequests];//if any...
	self.delegate = nil;
}

#pragma mark - Execution

-(void) execRequest:(RFRequest*)request {
	
	//check if something is already running...
	if (self.currentRequest) {
		//if it is, queue the request for later
		[self.requestsQueue addObject:request];
		RFLog(@"Request %@ queued", request);
		return;
	}
	
	self.currentRequest = request;
	NSURLRequest* urlRequest = [request urlRequest];
	
	if (urlConnection != nil) {
		urlConnection = nil;
	}
	
	RFLog(@"executing: %@", [request URL]);
//	urlConnection = [[NSURLConnection alloc] initWithRequest:urlRequest delegate:self startImmediately:YES];
	urlConnection = [[NSURLConnection alloc] initWithRequest:urlRequest delegate:self startImmediately:NO];
	
	[urlConnection scheduleInRunLoop:[NSRunLoop mainRunLoop]
                             forMode:NSDefaultRunLoopMode];
    [urlConnection start];
	
	
	if (self.delegate && [self.delegate respondsToSelector:@selector(restService:didStartLoadingRequest:)]) {
		[self.delegate restService:self didStartLoadingRequest:request];
	}
}

-(void) continueExecFromQueue
{
	assert(!self.currentRequest);
	if (self.requestsQueue.count == 0) {
		return;
	}
	
	RFRequest* r = [self.requestsQueue objectAtIndex:0];
	[self.requestsQueue removeObjectAtIndex:0]; //remove from queue
	RFLog(@"Executing queued request: %@", r);
	[self execRequest:r];
}

-(void) cancelRequests {
	
	if (urlConnection) {
		[urlConnection cancel];
		urlConnection = nil;
		webData = nil;
	}
	
	self.currentRequest = nil;
	requestsQueue = nil;
}

-(BOOL) hasRequestWithTag:(NSUInteger)tag
{
	if (self.currentRequest && self.currentRequest.tag == tag) {
		return YES;
	}
	
	for (RFRequest* r in self.requestsQueue) {
		if (r.tag == tag) {
			return YES;
		}
	}
	
	return NO;
}

#pragma mark -
#pragma mark NSURLConnection delegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	webData = [[NSMutableData alloc] init];
	
	httpCode = 200; //OK
	if ([response respondsToSelector:@selector(statusCode)])
	{
		httpCode = [(NSHTTPURLResponse*)response statusCode];
	}
}


-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	assert(webData != nil);
	[webData appendData:data];
	if (self.delegate && [self.delegate respondsToSelector:@selector(restService:loadedData:)]) {
		[self.delegate restService:self loadedData:[webData length]];
	}
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
	if (self.delegate && [self.delegate respondsToSelector:@selector(restService:sentData:totalBytesExpectedToSend:)]) {
		[self.delegate restService:self sentData:totalBytesWritten totalBytesExpectedToSend:totalBytesExpectedToWrite];
	}
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	webData = nil;
	urlConnection = nil;
	
	//notify
	if (self.delegate && [(NSObject*)self.delegate respondsToSelector:@selector(restService:didFinishWithResponse:)]) {
		[self.delegate restService:self didFinishWithResponse:[RFResponse responseWithRequest:self.currentRequest error:error statusCode:httpCode]];
	}
	
	//nil it
	self.currentRequest = nil;
	[self continueExecFromQueue];
}


-(void)connectionDidFinishLoading:(NSURLConnection *)connection {
	urlConnection = nil;
	
	if (self.delegate && [(NSObject*)self.delegate respondsToSelector:@selector(restService:didFinishWithResponse:)]) {
		[self.delegate restService:self didFinishWithResponse:[RFResponse 
														   responseWithRequest:self.currentRequest 
														   data:[NSData dataWithData:webData] 
														   statusCode:httpCode]];
	}
	
	webData = nil;
	
	//nil it
	self.currentRequest = nil;
	[self continueExecFromQueue];
}

#pragma mark - Class Methods

+(RFService*) execRequest:(RFRequest*)request completion:(RFRequestCompletion)completion
{
	RFService* svc = [[RFService alloc] init];
	svc.delegate = svc;
	svc.asyncDelegate = svc;
	svc.asyncCompletionBlock = completion;
	[svc execRequest:request];
	
	return svc;
}

+(RFService*) execRequest:(RFRequest*)request completion:(RFRequestCompletion)completion dataReceived:(void(^)(NSUInteger totalBytesReceived))dataReceivedBlock dataSent:(void(^)(NSUInteger totalBytesSent, NSUInteger totalBytesExpected))dataSentBlock
{
	RFService* svc = [[RFService alloc] init];
	svc.delegate = svc;
	svc.asyncDelegate = svc;
	svc.asyncCompletionBlock = completion;
	svc.dataReceivedlock = dataReceivedBlock;
	svc.dataSentBlock = dataSentBlock;
	[svc execRequest:request];
	
	return svc;
}

#pragma mark - SVC delegate

-(void) restService:(RFService *)svc didFinishWithResponse:(RFResponse *)response
{
	self.asyncCompletionBlock(response);
	self.asyncCompletionBlock = nil;
	self.asyncDelegate = nil;
}

-(void) restService:(RFService *)svc loadedData:(NSUInteger)bytes
{
	if (self.dataReceivedlock) {
		self.dataReceivedlock(bytes);
	}
}

-(void) restService:(RFService *)svc sentData:(NSUInteger)bytes totalBytesExpectedToSend:(NSUInteger)totalBytesExpected
{
	if (self.dataSentBlock) {
		self.dataSentBlock(bytes, totalBytesExpected);
	}
}

@end

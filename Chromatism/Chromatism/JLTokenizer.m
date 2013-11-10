//
//  Tokenizer.m
//  iGitpad
//
//  Created by Johannes Lund on 2012-11-24.
//
//

//  This file builds upon the work of Kristian Kraljic
//
//  RegexHighlightView.m
//  Simple Objective-C Syntax Highlighter
//
//  Created by Kristian Kraljic on 30/08/12.
//  Copyright (c) 2012 Kristian Kraljic (dikrypt.com, ksquared.de). All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

#import "JLTokenizer.h"
#import "JLTextViewController.h" 
#import "JLScope.h"
#import "JLTokenPattern.h"
#import "Chromatism.h"

#define BLOCK_COMMENT @"blockComment"
#define LINE_COMMENT @"lineComment"

@interface JLTokenizer ()

@property (nonatomic, strong) JLScope *documentScope;
@property (nonatomic, strong) JLScope *lineScope;
@property (nonatomic, strong) NSTimer *validationTimer;

@end

@implementation JLTokenizer
{
    NSRange _editedRange;
    NSRange _editedLineRange;
}

#pragma mark - Setup

- (void)setup
{
    JLScope *documentScope = [JLScope new];
    JLScope *lineScope = [JLScope new];
    
    NSDictionary *constants = [Chromatism constantIdentifiers];
    
    NSMutableDictionary *identifiedPatterns = [NSMutableDictionary new];
    
    // Let's read the objectivec.plist file and generate these dynamically!
    
    NSString *path = [[NSBundle mainBundle] pathForResource:@"css" ofType:@"plist"];
    NSDictionary *lexer = [NSDictionary dictionaryWithContentsOfFile:path];
    for (NSDictionary *pattern in [lexer objectForKey:@"Patterns"]) {
        NSString *token = [constants objectForKey:[pattern objectForKey:@"token"]];
        NSString *patternStr = [pattern objectForKey:@"pattern"];
        if (!patternStr)
            patternStr = @"";
        NSArray *scopes = [pattern objectForKey:@"scope"];
        for (NSString *scope in scopes) {
            JLTokenPattern *tokenPattern;
            JLScope *theScope;
            if ([scope isEqualToString:@"documentScope"])
                theScope = documentScope;
            else if ([scope isEqualToString:@"lineScope"])
                theScope = lineScope;
            else if ([[identifiedPatterns allKeys] containsObject:scope])
                theScope = [identifiedPatterns objectForKey:scope];
            else {
                NSLog(@"Scope %@ not found, skipping", scope);
                continue;
            }
            
            if ([pattern objectForKey:@"expressionOption"]) {
                NSString *option =[pattern objectForKey:@"expressionOption"];
                tokenPattern = [self addToken:token withIdentifier:[pattern objectForKey:@"identifier"] pattern:@"" andScope:theScope];
                if ([option isEqualToString:@"global"])
                    tokenPattern.expression = [NSRegularExpression regularExpressionWithPattern:patternStr options:NSRegularExpressionSearch error:nil];
                else
                    tokenPattern.expression = [NSRegularExpression regularExpressionWithPattern:patternStr options:NSRegularExpressionDotMatchesLineSeparators error:nil];
            } else {
                if ([pattern objectForKey:@"identifier"]) {
                    tokenPattern = [self addToken:token withIdentifier:[pattern objectForKey:@"identifier"] pattern:patternStr andScope:theScope];
                    [identifiedPatterns setObject:tokenPattern forKey:[pattern objectForKey:@"identifier"]];
                } else if ([pattern objectForKey:@"keywords"]) {
                    tokenPattern = [self addToken:token withKeywords:[pattern objectForKey:@"keywords"] andScope:theScope];
                } else {
                    NSLog(@"token %@ pattern %@ scope %@", token, patternStr, theScope);
                    tokenPattern = [self addToken:token withPattern:patternStr andScope:theScope];
                }
            }
            
            if ([pattern objectForKey:@"triggeringCharacterSet"]) {
                NSString *setStr = [pattern objectForKey:@"triggeringCharacterSet"];
                tokenPattern.triggeringCharacterSet = [NSCharacterSet characterSetWithCharactersInString:setStr];
            }
            
            if ([pattern objectForKey:@"captureGroup"]) {
                tokenPattern.captureGroup = [[pattern objectForKey:@"captureGroup"] integerValue];
            }
            
            if ([pattern objectForKey:@"opaque"]) {
                tokenPattern.opaque = [[pattern objectForKey:@"opaque"] boolValue];
            }
        }
    }
        
    [documentScope addSubscope:lineScope];
    
    self.documentScope = documentScope;
    self.lineScope = lineScope;
}

- (JLScope *)documentScope
{
    if (!_documentScope) [self setup];
    return _documentScope;
}

- (JLScope *)lineScope
{
    if (!_lineScope) [self setup];
    return _lineScope;
}

#pragma mark - NSTextStorageDelegate

- (void)textStorage:(NSTextStorage *)textStorage willProcessEditing:(NSTextStorageEditActions)editedMask range:(NSRange)editedRange changeInLength:(NSInteger)delta
{
    
}

- (void)textStorage:(NSTextStorage *)textStorage didProcessEditing:(NSTextStorageEditActions)editedMask range:(NSRange)editedRange changeInLength:(NSInteger)delta
{
    _editedRange = editedRange;
    _editedLineRange = [textStorage.string lineRangeForRange:editedRange];
    
    if (textStorage.editedMask == NSTextStorageEditedAttributes) return;
    
    [self tokenizeTextStorage:textStorage withRange:_editedLineRange];
//    [self setNeedsValidation:YES];
}

#pragma mark - JLScope delegate

- (void)scope:(JLScope *)scope didChangeIndexesFrom:(NSIndexSet *)oldSet to:(NSIndexSet *)newSet
{
    if ([self.delegate respondsToSelector:@selector(scope:didFinishProcessing:)]) [self.delegate scope:scope didFinishProcessing:self];
    NSLog(@"%i %i", [self.documentScope.subscopes containsObject:scope], scope!=self.lineScope);
    if ([self.documentScope.subscopes containsObject:scope] && scope != self.lineScope)
    {
        NSMutableIndexSet *removedIndexes = oldSet.mutableCopy;
        [removedIndexes removeIndexes:newSet];
        
        // Make sure the indexes still excist in the attributedString
        removedIndexes = [removedIndexes intersectionWithSet:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, scope.textStorage.length)]];
        
        ChromatismLog(@"Removed Indexes:%@",removedIndexes);
        
        if (removedIndexes) {
            [removedIndexes enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
                [self tokenizeTextStorage:scope.textStorage withRange:range];
            }];
        } 
    }
}

- (NSString *)mergedModifiedStringForScope:(JLScope *)scope
{
    NSString *oldString = [self.dataSource recentlyReplacedText];
    NSString *newString = [scope.string substringWithRange:_editedLineRange];
    if (oldString && newString) {
        return [oldString stringByAppendingString:newString];
    }
    return nil;
}

- (NSDictionary *)attributesForScope:(JLScope *)scope
{
    UIColor *color = self.colors[scope.type];
    NSAssert(color, @"Didn't get a color for type:%@ in colorDictionary: %@",scope.type, self.colors);
    return @{ NSForegroundColorAttributeName : color };
}

#pragma mark - Tokenizing

- (void)tokenizeTextStorage:(NSTextStorage *)textStorage
{
    [self tokenizeTextStorage:textStorage withRange:NSMakeRange(0, textStorage.length)];
}

- (void)tokenizeTextStorage:(NSTextStorage *)storage withRange:(NSRange)range
{
    // First, remove old attributes
    [self clearColorAttributesInRange:range textStorage:storage];
    
    [self.documentScope setTextStorage:storage];
    [self.documentScope setSet:[NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, storage.length)]];
    [self.lineScope setSet:[NSMutableIndexSet indexSetWithIndexesInRange:range]];
    
    [self.documentScope perform];
}

#pragma mark - Validation

/*
- (void)setNeedsValidation:(BOOL)needsValidation
{
    _needsValidation = needsValidation;
    if (needsValidation) {
        [self.validationTimer invalidate]; // This is not necessary, right?
        self.validationTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(validateTokenization) userInfo:nil repeats:NO];
    }
}

- (void)validateTokenization
{
    [self.textStorage beginEditing];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self tokenize];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setNeedsValidation:NO];
            [self.textStorage endEditing];
        });
    });
}
*/

- (NSMutableAttributedString *)tokenizeString:(NSString *)string withDefaultAttributes:(NSDictionary *)attributes;
{
    NSMutableAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string attributes:attributes].mutableCopy;
    [self tokenizeTextStorage:(NSTextStorage *)attributedString withRange:NSMakeRange(0, string.length)];
    return attributedString;
}

#pragma mark - Helpers

- (JLTokenPattern *)addToken:(NSString *)type withPattern:(NSString *)pattern andScope:(JLScope *)scope
{
    return [self addToken:type withIdentifier:type pattern:pattern andScope:scope];
}

- (JLTokenPattern *)addToken:(NSString *)type withIdentifier:(NSString *)identifier pattern:(NSString *)pattern andScope:(JLScope *)scope
{
    NSParameterAssert(type);
    NSParameterAssert(pattern);
    NSParameterAssert(scope);
    
    NSLog(@"type %@ identifier %@ pattern \"%@\" scope %@", type, identifier, pattern, scope);
    
    JLTokenPattern *token = [JLTokenPattern tokenPatternWithPattern:pattern];
    token.identifier = identifier;
    token.type = type;
    token.delegate = self;
    [scope addSubscope:token];
    
    return token;
}

- (JLTokenPattern *)addToken:(NSString *)type withKeywords:(NSString *)keywords andScope:(JLScope *)scope
{
    NSString *pattern = [NSString stringWithFormat:@"\\b(%@)\\b", [[keywords componentsSeparatedByString:@" "] componentsJoinedByString:@"|"]];
    return [self addToken:type withPattern:pattern andScope:scope];
}

- (void)clearColorAttributesInRange:(NSRange)range textStorage:(NSTextStorage *)storage;
{
    [storage removeAttribute:NSForegroundColorAttributeName range:range];
    [storage addAttribute:NSForegroundColorAttributeName value:self.colors[JLTokenTypeText] range:range];
}

@end

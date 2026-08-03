import Foundation

/// 注入 EPUB WebView 的 JS：
/// - SY.getSelectionInfo()  取选中文字 / 上下文 / 在章节纯文本中的偏移
/// - SY.highlightSelection(color)  给当前选区上色
/// - SY.markByOffset(text, offset) 重绘已保存的划线
/// - SY.setFontSize(px)           调整字号
enum ReaderJS {

    static let source = """
    (function() {
        if (window.SY) return;
        var SY = {};

        function selectionRange() {
            var sel = window.getSelection();
            if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return null;
            return sel.getRangeAt(0);
        }

        // 把 range 涉及的每个文本节点分别包上 span（跨节点 surroundContents 会抛错）
        function wrapRange(range, className, color) {
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                acceptNode: function(n) {
                    if (!n.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
                    try { return range.intersectsNode(n) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT; }
                    catch (e) { return NodeFilter.FILTER_REJECT; }
                }
            });
            var nodes = [];
            while (walker.nextNode()) nodes.push(walker.currentNode);
            nodes.forEach(function(n) {
                var r = document.createRange();
                r.selectNodeContents(n);
                if (n === range.startContainer) r.setStart(n, range.startOffset);
                if (n === range.endContainer) r.setEnd(n, range.endOffset);
                if (r.collapsed) return;
                var span = document.createElement('span');
                span.className = className;
                span.style.backgroundColor = color;
                try { r.surroundContents(span); } catch (e) {}
            });
        }

        SY.getSelectionInfo = function() {
            var range = selectionRange();
            if (!range) return null;
            var text = window.getSelection().toString().trim();
            if (!text) return null;

            // 只允许从文本节点开始的选择；拒绝块级元素被整体选中的情况
            var node = range.startContainer;
            if (node.nodeType !== 3) return null; // 必须是文本节点

            // 上下文：取选区所在块级元素的文本，或回退到整个 body
            var el = node.parentNode;
            var block = el && el.closest
                ? el.closest('p,li,blockquote,section,div,h1,h2,h3,h4')
                : null;
            var context = block ? block.innerText : document.body.innerText;
            context = context.slice(0, 1000); // 上下文截短到 1000 字，省 token

            // 选区起点在 body 纯文本中的偏移
            var bodyRange = document.createRange();
            bodyRange.selectNodeContents(document.body);
            try { bodyRange.setEnd(range.startContainer, range.startOffset); } catch (e) {}
            var start = bodyRange.toString().length;

            return { text: text, context: context, start: start };
        };

        SY.highlightSelection = function(color) {
            var range = selectionRange();
            if (!range) return false;
            wrapRange(range, 'sy-mark', color);
            window.getSelection().removeAllRanges();
            return true;
        };

        // 根据「文本 + 偏移」重绘划线
        SY.markByOffset = function(text, offset, color) {
            if (!text) return false;
            var end = offset + text.length;
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
            var pos = 0, startNode = null, startOff = 0, endNode = null, endOff = 0, n;
            while ((n = walker.nextNode())) {
                var len = n.nodeValue.length;
                if (startNode === null && pos + len > offset) {
                    startNode = n; startOff = offset - pos;
                }
                pos += len;
                if (startNode !== null && pos >= end) {
                    endNode = n; endOff = end - (pos - len);
                    break;
                }
            }
            if (!startNode || !endNode) return false;
            var range = document.createRange();
            range.setStart(startNode, startOff);
            range.setEnd(endNode, endOff);
            wrapRange(range, 'sy-mark', color);
            return true;
        };

        SY.setFontSize = function(px) {
            document.documentElement.style.fontSize = px + 'px';
            if (document.body) document.body.style.fontSize = px + 'px';
        };

        // 护眼模式切换
        SY.setTheme = function(theme) {
            document.documentElement.setAttribute('data-theme', theme);
            var body = document.body;
            if (!body) return;
            if (theme === 'green') {
                body.style.background = '#CCE8CF';
                body.style.color = '#1A2E1A';
            } else if (theme === 'dark') {
                body.style.background = '#1C1C1E';
                body.style.color = '#E8E6E1';
            } else {
                body.style.background = '#FBF9F4';
                body.style.color = '#2B2B2B';
            }
        };

        // 选段变化 → 通知 Swift 显示/隐藏动作条
        var lastText = '';
        document.addEventListener('selectionchange', function() {
            var info = SY.getSelectionInfo();
            var text = info ? info.text : '';
            if (text !== lastText) {
                lastText = text;
                if (text) {
                    // 把选区矩形也送上去，方便 Swift 侧定位悬浮条
                    var sel = window.getSelection();
                    var rect = {top:0,left:0,bottom:0,right:0};
                    if (sel && sel.rangeCount > 0) {
                        try {
                            var r = sel.getRangeAt(0).getBoundingClientRect();
                            rect = {top:r.top, left:r.left, bottom:r.bottom, right:r.right};
                        } catch(e) {}
                    }
                    info.rect = rect;
                }
                try {
                    window.webkit.messageHandlers.shuyou.postMessage(info || {text:'',context:'',start:0});
                } catch(e) {}
            }
        });

        // 点击网页空白处也通知 Swift 关闭
        document.addEventListener('touchend', function(e) {
            setTimeout(function() {
                var sel = window.getSelection();
                if (!sel || sel.isCollapsed || sel.toString().trim() === '') {
                    if (lastText !== '') {
                        lastText = '';
                        try {
                            window.webkit.messageHandlers.shuyou.postMessage({text:'',context:'',start:0});
                        } catch(e) {}
                    }
                }
            }, 50);
        });

        SY.clearSelection = function() {
            window.getSelection().removeAllRanges();
            lastText = '';
        };

        // 滚动位置上报（节流 300ms），供 Swift 侧保存阅读进度
        var scrollTimer = null;
        window.addEventListener('scroll', function() {
            if (scrollTimer) return;
            scrollTimer = setTimeout(function() {
                scrollTimer = null;
                try {
                    window.webkit.messageHandlers.shuyou.postMessage({type:'scroll', y:window.scrollY});
                } catch(e) {}
            }, 300);
        }, {passive:true});

        window.SY = SY;
    })();
    """

    static let css = """
    html { -webkit-text-size-adjust: none; -webkit-user-select: text; user-select: text; }
    body {
        margin: 0;
        padding: 28px 22px 20vh;
        line-height: 1.85;
        font-size: 18px;
        word-wrap: break-word;
        overflow-wrap: break-word;
        background: #FBF9F4;
        color: #2B2B2B;
        -webkit-user-select: text;
        user-select: text;
    }
    img, svg, image { max-width: 100%; height: auto; }
    p { margin: 0 0 0.9em; text-align: justify; }
    h1, h2, h3, h4 { line-height: 1.4; margin: 1.2em 0 0.8em; }
    a { color: inherit; text-decoration: none; }
    .sy-mark { border-radius: 2px; padding: 0 1px; }
    @media (prefers-color-scheme: dark) {
        body { background: #1C1C1E; color: #E8E6E1; }
    }
    """
}

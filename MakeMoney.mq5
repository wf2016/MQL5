//+------------------------------------------------------------------+
//|                                                    MakeMoney.mq5 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//|EURUSD单仓EA |
//+------------------------------------------------------------------+

#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade\AccountInfo.mqh>       //账户信息
#include <Trade\DealInfo.mqh>          //交易类 只针对已经发生了交易的
#include <Trade\HistoryOrderInfo.mqh>  //历史订单，可能包括没有交易成功的订单
#include <Trade\OrderInfo.mqh>         //订单类
#include <Trade\SymbolInfo.mqh>        //货币基础类
#include <Trade\PositionInfo.mqh>      //仓位
#include <Trade\Trade.mqh>             //交易类


//创建基本对象
CPositionInfo     myPosition;          //持仓对象
CSymbolInfo mySymbol;                  //品种(货币)对象
CAccountInfo myAccount;                //账户对象
CHistoryOrderInfo myHistoryOrderInfo;  //历史交易订单对象
CTrade myTrade;                        //交易对象
CDealInfo myDealInfo;                  //已经交易的订单对象（已经交易）

static double tradeLots=0.01;          //每次交易的手数
static double lastMinutePrice=0;       //最近一次整分钟点的价格（时时最新）
static double mvLastMinutePrice=0;     //最近一次整分钟点的价格（mvTimes日移动平均线）Moving Average
static int mvTimes=25;                 //移动平均线的频率 25天
static int compareStatus=0;            //mvTimes日均线价格和最新价格比较状态 0:mvTimes日均价大于最新价格 1:mvTimes.。小于最新价格
static int TRADE_SIGNAL_BUY=1;         //买入信号
static int TRADE_SIGNAL_SELL=0;        //卖出信号
static int TRADE_SIGNAL_NONE=-1;       //非交易信号
static int SAVING_TIME=0;              //急救时间 毫秒 600000十分钟
static double LOSS_MAX=-7;             //亏损百分比最大\
static int start_wait_minute =0;       //开始初始化等待的时间

bool INIT_SIGNAL =false;
bool SLEEP_SIGNAL =false;
int timeMinuteCount =0;                //走过的分钟


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //进行初始化前的安全校验
    bool check=checkInitTrade();
    if(!check){  
        printf("校验没有通过 不可以交易");
        return(INIT_FAILED);//校验没有通过 不可以交易
    }
    return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| 先获取当前是都有仓位，如果没有，那么在价格发生交叉的时候先开一单。(暂时不考虑线程同步的问题)                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
    //可以交易状态
    int type=110;
    bool close = true;
    
    printf("走过的分钟："+IntegerToString(timeMinuteCount));
    if(timeMinuteCount >=start_wait_minute){ 
        //过了是N分钟之后再开始交易
        if(!INIT_SIGNAL){
            initStart();
            INIT_SIGNAL = true;
        }
        if(INIT_SIGNAL){
            double minuteProfit = getEveryMinuteProfit();
            if(minuteProfit <=LOSS_MAX ){
                //亏损太多，强制平仓了
                ulong ticket=PositionGetTicket(0);
                myTrade.PositionClose(ticket,0); 
                printf("亏太多了，强制平仓。利润："+DoubleToString(minuteProfit,5));
                close = false;
            }
            if(close){
                int status=getChangeStatus();
                if(status==1 || status==0){
                    type=openPosition(status);
                }
            }  
        }
    }
    
    priceChange();  //调用价格转变函数
    if(type==120 || !close){
        //  printf("急救时间");
        //  Sleep(SAVING_TIME);//急救时间
    }
}


//+------------------------------------------------------------------+
//|开仓|                                                                  |
//+------------------------------------------------------------------+
int  openPosition(int status)
{
    bool isHavePosition=PositionSelect(_Symbol);
    int changeStatus=status;
    if(!isHavePosition){
        //手中没有仓 那么先开一仓  
        if(changeStatus==1){
            myTrade.Buy(tradeLots,_Symbol);
            printf("买入成功:"+TimeToString(TimeCurrent(),TIME_MINUTES));
        }else if(changeStatus==0){
            myTrade.Sell(tradeLots,_Symbol);
            printf("卖空成功:"+TimeToString(TimeCurrent(),TIME_MINUTES));
        }else if(changeStatus==-1){
            //  printf("没有出现交叉");
        } else{
            printf("数据异常");
        }
    } else{
        //手中有一仓，坐等平仓了 先计算利润 
        double positionProfit=getPositionProfit();
        if(positionProfit>=10){
            ulong ticket=PositionGetTicket(0);
            myTrade.PositionClose(ticket);
            printf("平仓成功,利润为："+DoubleToString(positionProfit,5));
            return 120;//平仓之后休息一下
        }
    }
    return 110;
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double getPositionProfit()
{
    int total=PositionsTotal();
    if(total>=1){
        ulong ticket=PositionGetTicket(0);
        myPosition.SelectByTicket(ticket);
        //double  moneyTotal=myPosition.Volume() *myPosition.PriceOpen()*1000;//这一仓花费的金额
        return myPosition.Profit();
    }else{
        return 0;
    }
    //printf("proficPercent:"+profit/100);
}



//+------------------------------------------------------------------+
//|检查当前是否可以交易（仅仅用在初始化的时候）
//+------------------------------------------------------------------+
bool checkInitTrade()
{
    //查看当前交易品种
    if(!mySymbol.Name("EURUSD")){
        printf("当前品种不是EURUSD,不进行交易！！！");
        return false;
    }
    
    //查看当前账号
    //long  accountId = 7345113 ;
    long  accountId=7345113;
    if(!myAccount.Login()==accountId){
        printf("当前登录账号不对,不能进行交易！！！");
        //    return false;
    }
    
    //查看当前交易模式
    if(!myAccount.TradeMode()==ACCOUNT_TRADE_MODE_DEMO){
        printf("当前账号交易模式不是模拟账户,不进行交易！！！");
        return false;
    }
    
    //确保是线程安全！！！！
    if(!myAccount.TradeAllowed() || !myAccount.TradeExpert() || !mySymbol.IsSynchronized()){
        printf("账户异常,不能交易！！！");
        return false;
    }
        
    int ordersTotal=OrdersTotal();//当前挂单量
    if(ordersTotal>0){
        printf("当前账户有未完成的订单，不能继续交易！！");
        return false;
    }
    return true;
}


//+------------------------------------------------------------------+
//|初始化数据 在初始化的时候调用
//+------------------------------------------------------------------+
void initStart()
{
    
    int nowMinutePrice=iMA(Symbol(),0,1,0,MODE_SMA,PRICE_CLOSE);                //实时价格
    int mvMinutePrice=iMA(Symbol(),PERIOD_M1,mvTimes,0,MODE_SMA,PRICE_CLOSE);   //每分钟 mvTimes 均线
    double mvMinutePriceList[];     //分钟价格
    double nowMinutePriceList[];    //时时价格
    ArraySetAsSeries(mvMinutePriceList,true);
    ArraySetAsSeries(nowMinutePriceList,true);
    CopyBuffer(mvMinutePrice,0,0,2,mvMinutePriceList);
    CopyBuffer(nowMinutePrice,0,0,2,nowMinutePriceList);
    
    //1为 上一分钟价格  0 为时时价格
    mvLastMinutePrice= mvMinutePriceList[1];    //初始化第一分钟价格 mv
    lastMinutePrice = nowMinutePriceList[1];    //初始化第一分钟价格 now                                         
    //获取已经成交的交易总数
    printf("初始化价格成功："+TimeToString(TimeCurrent(),TIME_SECONDS));
    printf("分钟价格为："+DoubleToString(lastMinutePrice,8));
    printf("mvTimes分钟价格为："+DoubleToString(mvLastMinutePrice,8));
}


//+------------------------------------------------------------------+
//|返回交易信号
//+------------------------------------------------------------------+
int getChangeStatus()
{
    int iMAPriceIndex=iMA(Symbol(),0,1,0,MODE_SMA,PRICE_CLOSE);                     //获取时时分钟价格 
    double nowPriceList[];                                                          //时时价格
    ArraySetAsSeries(nowPriceList,true);
    CopyBuffer(iMAPriceIndex,0,0,2,nowPriceList);
    double nowPrice=nowPriceList[1];
    
    int iMA25PriceIndex=iMA(Symbol(),PERIOD_M1,mvTimes,0,MODE_SMA,PRICE_CLOSE);     //获取时时分钟价格 mvTimes日均价
    double mvNowPriceList[];                                                        //mvTimes日价格线
    ArraySetAsSeries(mvNowPriceList,true);
    CopyBuffer(iMA25PriceIndex,0,0,2,mvNowPriceList);
    double mvNowPrice=mvNowPriceList[1];
    
    // printf("lastMinutePrice:"+lastMinutePrice);
    // printf("nowPrice:"+nowPrice);
    if(lastMinutePrice!=nowPrice && mvLastMinutePrice!=mvNowPrice){
        if(((lastMinutePrice-mvLastMinutePrice>0) && (nowPrice-mvNowPrice<0)) || ((lastMinutePrice-mvLastMinutePrice)<0 && (nowPrice-mvNowPrice)>0)){
            //价格出现了交叉 可以下单了
            //判断应该买入还是卖出
            if(nowPrice-mvNowPrice>0){
                //买入 时时价格变为在上方
                printf("买入信号");
                return TRADE_SIGNAL_BUY;
            }else if(nowPrice<mvNowPrice){
                //卖出
                printf("卖出信号");
                return TRADE_SIGNAL_SELL;
            }
        }else{
            // printf("什么都不是："+TimeToString(TimeCurrent(),TIME_SECONDS));
            return TRADE_SIGNAL_NONE;
        }
    }
    return TRADE_SIGNAL_NONE;
}


//+------------------------------------------------------------------+
//|指标价格向前一分钟
//+------------------------------------------------------------------+
void priceChange()
{
    //判断是否发生时间转变 时间转变的判断是 mvTimes日平均价格或者时时价格发生了变化
    int iMAPriceIndex=iMA(Symbol(),0,1,0,MODE_SMA,PRICE_CLOSE);                 //获取时时分钟价格 
    double nowPriceList[];                                                      //时时价格
    ArraySetAsSeries(nowPriceList,true);
    CopyBuffer(iMAPriceIndex,0,0,2,nowPriceList);
    double nowPrice=nowPriceList[1];
    
    int iMA25PriceIndex=iMA(Symbol(),PERIOD_M1,mvTimes,0,MODE_SMA,PRICE_CLOSE); //获取时时分钟价格 mvTimes日均价
    double mvNowPriceList[];                                                    //mvTimes日价格线
    ArraySetAsSeries(mvNowPriceList,true);
    CopyBuffer(iMA25PriceIndex,0,0,2,mvNowPriceList);
    double mvNowPrice=mvNowPriceList[1];
    
    //printf("nowPrice:"+nowPrice);
    //printf("mvNowPrice:"+mvNowPrice);
    if(mvNowPrice!=mvLastMinutePrice && lastMinutePrice!=nowPrice){
        timeMinuteCount++;
        // printf("timeMinuteCount:"+timeMinuteCount);
        //时间交换  往前推进一分钟
        lastMinutePrice=nowPrice;
        mvLastMinutePrice=mvNowPrice;
        //   printf("价格出现了变化:"+TimeToString(TimeCurrent(),TIME_SECONDS));
    }
}


//+------------------------------------------------------------------+
//|获取每一分钟之后结束的利润                                                                  |
//+------------------------------------------------------------------+
double getEveryMinuteProfit()
{
    //判断是否发生时间转变 时间转变的判断是 mvTimes日平均价格或者时时价格发生了变化
    double minuteProfit = 0;
    int iMAPriceIndex=iMA(Symbol(),0,1,0,MODE_SMA,PRICE_CLOSE);             //获取时时分钟价格 
    double nowPriceList[];                                                  //时时价格
    ArraySetAsSeries(nowPriceList,true);
    CopyBuffer(iMAPriceIndex,0,0,2,nowPriceList);
    double nowPrice=nowPriceList[1];
    
    int iMA25PriceIndex=iMA(Symbol(),PERIOD_M1,25,0,MODE_SMA,PRICE_CLOSE);  //获取时时分钟价格 mvTimes日均价
    double mvNowPriceList[];                                                //mvTimes日价格线
    ArraySetAsSeries(mvNowPriceList,true);
    CopyBuffer(iMA25PriceIndex,0,0,2,mvNowPriceList);
    double mvNowPrice=mvNowPriceList[1];
    if(mvNowPrice!=mvLastMinutePrice && lastMinutePrice!=nowPrice){
        return getPositionProfit();
    }   
    return minuteProfit;
}
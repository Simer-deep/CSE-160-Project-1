/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;
}

implementation{
   pack sendPackage;
   uint16_t sequenceNum = 0; //Sequence incr++

   uint16_t seenSrc[15];
   uint16_t seenSeq[15];
   uint16_t Scount = 0;
   uint16_t Snext = 0;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   void rememberPacket(uint16_t src, uint16_t seq)
   {
      seenSrc[Snext] = myMsg->src;
      seenSeq[Snext] = myMsg->seq;

      Snext = (Snext + 1) % 15;

      if(Scount < 15)
      {
         Scount++;
      }
   }

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

      uint16_t i;
      pack forwardPackage;

      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){ //take all information and fill it in to the flooding channel
         pack* myMsg=(pack*) payload;
         dbg(GENERAL_CHANNEL, "Node %d received src=%d dest=%d seq=%d TTL=%d protocol=%d\n",
         TOS_NODE_ID,
         myMsg->src,
         myMsg->dest,
         myMsg->seq,
         myMsg->TTL,
         myMsg->protocol
         );

         for(i = 0; i < Scount; i++)
         {
            if(seenSrc[i] == myMsg->src && seenSeq[i] == myMsg->seq)
            {
               return msg;
            }
         }

         rememberPacket(myMsg->src, myMsg->seq);

         if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PING) // Is this for me and protocol is ping. If yes then send back as protocol reply
            {

               makePack(
                  &sendPackage, 
                  TOS_NODE_ID, 
                  myMsg->src, 
                  MAX_TTL, 
                  PROTOCOL_PINGREPLY, 
                  sequenceNum, 
                  myMsg->payload, 
                  PACKET_MAX_PAYLOAD_SIZE
               );
               rememberPacket(TOS_NODE_ID, sequenceNum);

               sequenceNum++; 
               call Sender.send(sendPackage, AM_BROADCAST_ADDR);
            }

         if(myMsg->dest == TOS_NODE_ID){
            if(myMsg->protocol == PROTOCOL_PINGREPLY){
               dbg(GENERAL_CHANNEL, "Ping reply recieved from %d\n", myMsg->src);
            }

            return msg;
         }

         if(myMsg->TTL == 0){ //if time to live goes to 0 we drop msg
            return msg;
         }

         forwardPackage = *myMsg;
         forwardPackage.TTL--;

         call Sender.send(forwardPackage, AM_BROADCAST_ADDR);

         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      
      makePack(
         &sendPackage, 
         TOS_NODE_ID, 
         destination, 
         MAX_TTL, 
         PROTOCOL_PING, 
         sequenceNum, 
         payload, 
         PACKET_MAX_PAYLOAD_SIZE
      );

      rememberPacket(TOS_NODE_ID, sequenceNum);

      sequenceNum++; 
      call Sender.send(sendPackage, AM_BROADCAST_ADDR); // Send this radio frame to every node that is physically one hop away from me (AM_BORADCAST).
   }

   event void CommandHandler.printNeighbors(){}

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}

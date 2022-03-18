pragma solidity >=0.4.22 <0.9.0;

//import  "./Queue.sol";
import "./user.sol";

contract SupplyChain is User {

  struct Node{
    address owner;
    uint ownerId;
    uint itemid;
    uint[] precedents;
    bool isRetail;
    uint cost;            //cost at which this item will be sold to next person in the chain.

  }
  struct Order{
    uint buyerId;
    uint sellerId;
    uint itemId;     
    uint prevItemNodeId;     //from prevItemNodeID we can fetch the owner also, i.e, the seller.
  }


  mapping (uint => Order) orders;  //OrderID to orders mapping
  mapping(uint=> bool) orderShippingSatus;  //OrderID to shipping status mapping
  uint orderID=1;
  mapping(uint => Node) public nodes;   //Mapping from nodeID to nodes
  uint totalNodes=1;        //Keeps track of the index of the current node
  mapping(uint => uint) lastNodes;    //ItemID mapped to the last node (nodeID) of that particular item
  mapping(uint => mapping(uint => uint)) itemIdtoOwnerIdtoNodeId;  //This mappping helps in the case when we add a connection to the node for the second or subsequent times. It will help us access the nodeID which was assigned to this node when it was first created.
  event orderReceived(uint _orderid);
  event History(uint parent_itemId, uint[] children_itemIds);
  event orderShipped(uint _orderid);
  event StartingNode(uint _node);
  event orderRequested (uint _orderid);


  //Adds new user to the Dapp
  function addStartingNode(uint _userId, uint _itemId, string memory _itemName, bool _isRetail, uint _cost) external returns(uint){
    uint [] memory firstPrecedent;
    uint node = totalNodes;
    nodes[node] = Node(msg.sender, _userId, _itemId, firstPrecedent, _isRetail, _cost);
    lastNodes[_itemId]=node;
    itemIdtoOwnerIdtoNodeId[_itemId][_userId]= node;
    userStock[_userId].push(Stock(_itemId, _itemName,_cost,_isRetail));
    totalNodes+=1;
    emit StartingNode(node);
    return node;
  }


  function addTransaction(uint _userId, uint _orderID, uint _itemId, string memory _itemName, bool _isRetail, uint _cost) external payable {

      //uint prevNodeId=1;
      uint prevNodeId= orders[_orderID].prevItemNodeId;
      require( prevNodeId != 0 , "Call addStartingNode() function to add the starting node of the chain.");
      require (userIdtoAddress[_userId] == msg.sender, "Invaild user");
      require( isLastNode(orders[_orderID].prevItemNodeId), "Transfer possible only from last node of an itemID in the supply chain");
      //This additional check iensures that there is an approval from the sender side also before the receiver adds the node in the chain
      require( orderShippingSatus[_orderID] == true, "Order yet not shipped");  
       // Buyer should pay the exact amount of the previous node
      require (msg.value == nodes[prevNodeId].cost);  
   
      if(itemIdtoOwnerIdtoNodeId[_itemId][_userId] == 0) {   //First time taking raw material for a particular node (itemid,owner)
        uint[] memory firstPrecedent= new uint[](1);     //way to create dynamic "memory" array in Solidity
        firstPrecedent[0]=prevNodeId;   
        nodes[totalNodes]= Node(userIdtoAddress[_userId], _userId, _itemId, firstPrecedent, _isRetail, _cost);
       // uint node= totalNodes;
        itemIdtoOwnerIdtoNodeId[_itemId][_userId] = totalNodes;
        lastNodes[_itemId]=totalNodes;
        totalNodes+=1;

      }

      //
      else{
        uint currNodeId= itemIdtoOwnerIdtoNodeId[_itemId][_userId];
        nodes[currNodeId].precedents.push(prevNodeId);
        nodes[currNodeId].cost=_cost;
      }

      uint sellerId= nodes[prevNodeId].ownerId;
      updateStockforBuyer(_userId,_itemId, _itemName, _isRetail, _cost);
      deleteRequestedOrders(_userId, _orderID);
      deleteReceivedOrders(sellerId, _orderID);

      emit orderReceived(_orderID);

  }


  function isLastNode(uint _node) public view returns (bool) {

     return lastNodes[nodes[_node].itemid] == _node;
  }

  function orderRequest(uint _buyerId, uint _itemId, string memory _itemName, uint _sellerId) external returns(uint) {

   // orders[orderID]= Order(_buyerId, _sellerId, _itemId, 1);
   uint prevNodeId = itemIdtoOwnerIdtoNodeId[_itemId][_sellerId];
   address buyer= userIdtoAddress[_buyerId];
   require(buyer == msg.sender, "Please send the correct buyer id");
    orders[orderID]= Order(_buyerId, _sellerId, _itemId, prevNodeId);
   
    userRequestedOrder[_buyerId].push(RequestedOrder(_itemId, _sellerId, _itemName, orderID));
    userIdtoOrderIdtoReqOrderInd[_buyerId][orderID]= userRequestedOrder[_buyerId].length -1 ;

    userReceivedOrder[_sellerId].push(ReceivedOrder(_itemId, _buyerId, _itemName, orderID,false));
    userIdtoOrderIdtoRecOrderInd[_sellerId][orderID] = userReceivedOrder[_sellerId].length -1 ;

    updateStockforSeller(_sellerId, _itemId);  
    orderID+=1;

    emit orderRequested(orderID);
    return orderID;
  }




  function orderShipping(uint _orderID) external {
    uint sellerId= orders[_orderID].sellerId;
    require(userIdtoAddress[sellerId]== msg.sender);
    orderShippingSatus[_orderID]= true;
    uint arrInd= userIdtoOrderIdtoRecOrderInd[sellerId][_orderID];
    userReceivedOrder[sellerId][arrInd].isShipped = true;
    emit orderShipped(_orderID);
  }

  uint[] queue;

  int first;
  int last;
      //uint size=0;
  function enqueue(uint data) internal {
    last += 1;
        //  queue[last] = data;
    queue.push(data);
    if(queue.length==1)
      first=0;
  }

  function dequeue() internal {
    require(last >= first);  // non-empty queue
    //uint data = queue[first];
    delete queue[uint(first)];
    first += 1;
    if(queue.length==0)
    {
      first=-1;
      last=-1;
    }
  }


  function getHistory(uint _itemId) external {

    require( nodes[lastNodes[ _itemId]].isRetail == true);

    //currNode = nodes[lastNodes[_itemId]];
   // mapping(uint => bool) memory visited;     //NodeID to visted or not flag mapping
    delete queue;
    first=-1;
    last=-1;
    enqueue(lastNodes[_itemId]);
    //visited[lastNodes[_itemId]] = true;

    while(last>=0 && first>=0 && last>=first) // Condition to check that the queue is not empty 
    {

        uint currNodeid= queue[uint(first)];
        uint[] memory children_itemIds= new uint[](nodes[currNodeid].precedents.length);
        dequeue();

        for(uint i=0; i<nodes[currNodeid].precedents.length; i++) {

          //if(visited[nodes[currNodeid].precedents[i]] != true) {
          uint temp_itemId= nodes[nodes[currNodeid].precedents[i]].itemid;
          enqueue(nodes[currNodeid].precedents[i]);
          children_itemIds[i]= temp_itemId;
         // last=last-1;
        
        }
      emit History(nodes[currNodeid].itemid, children_itemIds);

    
    }
  }

}
#ifndef BASKET_RECOVERY_SHARED_CRC32_MQH
#define BASKET_RECOVERY_SHARED_CRC32_MQH

class CCrc32
  {
private:
   static uint       ReflectBits(uint value,const int bitCount)
     {
      uint result=0;
      for(int i=0;i<bitCount;i++)
        {
         if((value & (1 << i))!=0)
            result|=(1 << (bitCount-1-i));
        }
      return result;
     }

public:
   static uint       Compute(const string &text)
     {
      uint crc=0xFFFFFFFF;
      int length=StringLen(text);
      for(int i=0;i<length;i++)
        {
         uchar byte=(uchar)StringGetCharacter(text,i);
         crc^=byte;
         for(int bit=0;bit<8;bit++)
           {
            if((crc & 1)!=0)
               crc=(crc >> 1) ^ 0xEDB88320;
            else
               crc=crc >> 1;
           }
        }
      return crc ^ 0xFFFFFFFF;
     }

   static string     ToHex(const uint crc)
     {
      return StringFormat("%08X",crc);
     }

   static bool         FromHex(const string hexValue,uint &outCrc)
     {
      if(StringLen(hexValue)!=8)
         return false;
      outCrc=(uint)StringToInteger("0x"+hexValue);
      return true;
     }
  };

#endif

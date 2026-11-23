import sharp from 'sharp';
import { HttpError } from './auth.mjs';

let active = 0;
export async function prepareAvatar(value) {
  if (value === null) return '';
  if (typeof value !== 'string' || !value.length || value.length > 2_800_000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    throw new HttpError(400,'Choose an image smaller than 2 MB.');
  }
  const input = Buffer.from(value,'base64');
  if (input.length > 2*1024*1024) throw new HttpError(400,'Choose an image smaller than 2 MB.');
  const png=input.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
  const jpeg=input[0]===255 && input[1]===216 && input[2]===255;
  const webp=input.subarray(0,4).toString()==='RIFF' && input.subarray(8,12).toString()==='WEBP';
  if (!png && !jpeg && !webp) throw new HttpError(400,'Choose a valid JPG, PNG or WebP photo.');
  if (active >= 2) throw new HttpError(503,'Photo processing is busy. Please try again.');
  active++;
  try {
    const image = sharp(input,{limitInputPixels:16_000_000,failOn:'warning'});
    const metadata = await image.metadata();
    if (!['jpeg','png','webp'].includes(metadata.format) || (metadata.pages || 1)>1) throw new Error('Unsupported image.');
    const photo = await image.rotate().resize(256,256,{fit:'cover'}).flatten({background:'#FFFDF3'}).jpeg({quality:85}).toBuffer();
    return 'data:image/jpeg;base64,'+photo.toString('base64');
  } catch {
    throw new HttpError(400,'Choose a valid JPG, PNG or WebP photo.');
  } finally { active--; }
}
